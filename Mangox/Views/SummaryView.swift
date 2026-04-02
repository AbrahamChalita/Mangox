import SwiftUI
import SwiftData
import os.log

private let summaryLogger = Logger(subsystem: "com.abchalita.Mangox", category: "SummaryView")

private struct SummaryDataSignature: Equatable {
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

// MARK: - Wide Layout Environment Key

private struct IsWideSummaryKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isWideSummary: Bool {
        get { self[IsWideSummaryKey.self] }
        set { self[IsWideSummaryKey.self] = newValue }
    }
}

// MARK: - SummaryView

struct SummaryView: View {
    let workoutID: UUID
    @Environment(RouteManager.self) private var routeManager
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(StravaService.self) private var stravaService
    @Binding var navigationPath: NavigationPath

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]
    @Query private var allProgress: [TrainingPlanProgress]

    @State private var shareItems: [Any] = []
    @State private var lastExportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showExportModal = false
    @State private var actionError: String?
    @State private var selectedExportFormat: ExportFormat = .tcx
    @State private var stravaStatus: String?
    @State private var lastUploadedActivityID: Int?
    @State private var stravaTitleInput: String = ""
    @State private var stravaDescriptionInput: String = ""
    @State private var stravaDraftWorkoutID: UUID?
    @State private var uploadAsVirtualRide: Bool = true
    @State private var uploadPhotoAfterUpload: Bool = true
    @State private var showDescriptionPreview: Bool = false
    /// When false, generated Strava description omits the duration line (Strava still shows elapsed time on the activity).
    @AppStorage("stravaUploadDescriptionIncludeDuration") private var stravaIncludeDurationInDescription = true
    @AppStorage("stravaUploadDescriptionIncludeDistance") private var stravaIncludeDistanceInDescription = true
    @AppStorage("stravaUploadDescriptionIncludeCalories") private var stravaIncludeCaloriesInDescription = true
    @AppStorage("stravaUploadPreferredGearID") private var stravaPreferredGearID = ""
    @State private var commuteStravaUpload = false
    @State private var heroAppeared = false
    @State private var showStravaCard = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isWide: Bool { hSizeClass != .compact }

    // Cached computed data (populated once in .task)
    @State private var cachedSortedSamples: [WorkoutSample]?
    @State private var cachedSortedLaps: [LapSplit]?
    @State private var cachedZoneBuckets: [ZoneBucket]?
    @State private var cachedHRZoneBuckets: [HRZoneBucket]?
    @State private var dataReady = false
    @State private var preparedSignature: SummaryDataSignature?

    private let bg = AppColor.bg

    init(
        workoutID: UUID,
        navigationPath: Binding<NavigationPath>
    ) {
        self.workoutID = workoutID
        self._navigationPath = navigationPath
        let id = workoutID
        self._workouts = Query(filter: #Predicate<Workout> { workout in
            workout.id == id
        })
    }

    private var workout: Workout? {
        if let found = workouts.first {
            return found
        }
        let id = workoutID
        let descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private var sortedSamples: [WorkoutSample] {
        cachedSortedSamples ?? []
    }

    private var sortedLaps: [LapSplit] {
        cachedSortedLaps ?? []
    }

    private var dominantZone: PowerZone {
        guard let workout else { return PowerZone.zones[0] }
        return PowerZone.zone(for: Int(workout.avgPower))
    }

    private var workoutDataSignature: SummaryDataSignature? {
        guard let workout else { return nil }
        return SummaryDataSignature(
            workoutStatus: workout.statusRaw,
            duration: workout.duration,
            distance: workout.distance,
            avgPower: workout.avgPower,
            normalizedPower: workout.normalizedPower,
            tss: workout.tss,
            elevationGain: workout.elevationGain,
            savedRouteName: workout.savedRouteName,
            sampleCount: workout.sampleCount,
            lapCount: workout.laps.count,
            lastSampleElapsed: workout.sampleCount,
            lastLapNumber: workout.laps.count
        )
    }

    @ViewBuilder
    private var stravaButtonLabel: some View {
        if stravaService.isBusy {
            ProgressView()
                .tint(.white)
        } else {
            Image(systemName: lastUploadedActivityID != nil ? "checkmark.circle.fill" : "paperplane.fill")
        }
    }

    private var stravaButtonTint: Color {
        if lastUploadedActivityID != nil {
            return AppColor.success
        } else if stravaService.isConnected {
            return .white
        } else {
            return AppColor.orange
        }
    }

    private var stravaToolbarButton: some View {
        Button {
            if lastUploadedActivityID != nil {
                openStravaActivity()
            } else {
                showStravaCard = true
            }
        } label: {
            stravaButtonLabel
        }
        .disabled(stravaService.isBusy)
        .tint(stravaButtonTint)
    }

    private func invalidatePreparedData(resetHero: Bool = false) {
        dataReady = false
        preparedSignature = nil
        stravaDraftWorkoutID = nil
        if resetHero {
            heroAppeared = false
        }
        cachedSortedSamples = nil
        cachedSortedLaps = nil
        cachedZoneBuckets = nil
        cachedHRZoneBuckets = nil
    }

    private func prepareData(force: Bool = false) {
        guard let workout else {
            invalidatePreparedData(resetHero: true)
            return
        }
        guard let signature = workoutDataSignature else { return }
        guard force || preparedSignature != signature else { return }
        let samples = workout.samples.sorted { $0.elapsedSeconds < $1.elapsedSeconds }
        cachedSortedSamples = samples
        cachedSortedLaps = workout.laps.sorted { $0.lapNumber < $1.lapNumber }

        let totalSamples = max(samples.count, 1)
        var powerCounts = Dictionary(uniqueKeysWithValues: PowerZone.zones.map { ($0.id, 0) })
        var hrCounts = Dictionary(uniqueKeysWithValues: HeartRateZone.zones.map { ($0.id, 0) })
        var hrSampleCount = 0

        for sample in samples {
            let zone = PowerZone.zone(for: sample.power)
            powerCounts[zone.id, default: 0] += 1
            if sample.heartRate > 0 {
                let hrZone = HeartRateZone.zone(for: sample.heartRate)
                hrCounts[hrZone.id, default: 0] += 1
                hrSampleCount += 1
            }
        }

        cachedZoneBuckets = PowerZone.zones.map { zone in
            let count = powerCounts[zone.id, default: 0]
            return ZoneBucket(zone: zone, seconds: count, percent: Double(count) / Double(totalSamples))
        }

        let totalHR = max(hrSampleCount, 1)
        cachedHRZoneBuckets = HeartRateZone.zones.map { zone in
            let count = hrCounts[zone.id, default: 0]
            return HRZoneBucket(zone: zone, seconds: count, percent: Double(count) / Double(totalHR))
        }

        preparedSignature = signature
        dataReady = true
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if let workout {
                if dataReady {
                    SummaryContentView(
                        workout: workout,
                        sortedLaps: sortedLaps,
                        zoneBuckets: zoneBuckets,
                        hrZoneBuckets: hrZoneBuckets,
                        heroAppeared: heroAppeared,
                        showExportModal: $showExportModal,
                        selectedExportFormat: $selectedExportFormat,
                        lastExportedFileURL: lastExportedFileURL,
                        onDone: { navigationPath = NavigationPath() },
                        onDelete: { showDeleteConfirmation = true },
                        onOpenStravaUploader: { openStravaUploader() }
                    )
                    .environment(\.isWideSummary, isWide)
                } else {
                    loadingPlaceholder
                }
            } else {
                workoutNotFound
            }
        }
        .navigationTitle("Ride Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if stravaService.isConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    stravaToolbarButton
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showExportModal = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showExportModal) {
            if let workout {
                exportSheet(for: workout)
            }
        }
        .sheet(isPresented: $showStravaCard) {
            if let workout {
                stravaSheet(for: workout)
            }
        }
        .alert("Delete Ride?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This ride and all recorded data will be permanently removed. If this was a training plan workout, it will be un-marked as completed.")
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task {
            prepareData()
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                heroAppeared = true
            }
        }
        .onChange(of: workoutDataSignature) { _, newSignature in
            guard newSignature != nil else {
                invalidatePreparedData(resetHero: true)
                return
            }
            prepareData(force: true)
        }
        .onChange(of: workouts) { _, newWorkouts in
            // After deletion the filtered @Query is empty — drop cached graphs so we never
            // flash stale content if the view is reused or navigation is odd.
            if newWorkouts.isEmpty {
                invalidatePreparedData(resetHero: true)
            }
        }
    }

    // MARK: - Loading / Not Found

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white.opacity(0.4))
            Text("Pulling up your data")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var workoutNotFound: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.2))
            Text("Workout Not Found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text("The selected workout no longer exists.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
            Button("Back") { popFromSummary() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.mango)
                .padding(.top, 6)
        }
    }

    // MARK: - Zone Bucket Calculations

    private var zoneBuckets: [ZoneBucket] {
        cachedZoneBuckets ?? PowerZone.zones.map { ZoneBucket(zone: $0, seconds: 0, percent: 0) }
    }

    private var hrZoneBuckets: [HRZoneBucket] {
        cachedHRZoneBuckets ?? HeartRateZone.zones.map { HRZoneBucket(zone: $0, seconds: 0, percent: 0) }
    }

    // MARK: - Export Sheet

    private func exportSheet(for workout: Workout) -> some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    ExportSheetContent(
                        workout: workout,
                        selectedExportFormat: $selectedExportFormat,
                        lastExportedFileURL: lastExportedFileURL,
                        onExport: { fmt in
                            exportWorkout(workout: workout, format: fmt)
                            showExportModal = false
                        },
                        onOpenStravaUploader: { openStravaUploader() }
                    )
                    .padding(20)
                }
            }
            .navigationTitle("Export & Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showExportModal = false }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Strava Sheet

    private func stravaSheet(for workout: Workout) -> some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    StravaSheetContentView(
                        workout: workout,
                        stravaTitleInput: $stravaTitleInput,
                        stravaDescriptionInput: $stravaDescriptionInput,
                        includeDurationInDescription: $stravaIncludeDurationInDescription,
                        includeDistanceInDescription: $stravaIncludeDistanceInDescription,
                        includeCaloriesInDescription: $stravaIncludeCaloriesInDescription,
                        commuteStravaUpload: $commuteStravaUpload,
                        preferredGearID: $stravaPreferredGearID,
                        uploadAsVirtualRide: $uploadAsVirtualRide,
                        uploadPhotoAfterUpload: $uploadPhotoAfterUpload,
                        showDescriptionPreview: $showDescriptionPreview,
                        stravaStatus: stravaStatus,
                        lastUploadedActivityID: lastUploadedActivityID,
                        onResetDescriptionTemplate: { applyStravaDescriptionTemplate(for: workout) },
                        onUpload: { uploadToStrava(workout: workout) },
                        onOpenActivity: { openStravaActivity() }
                    )
                    .padding(20)
                }
            }
            .navigationTitle("Upload to Strava")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showStravaCard = false }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { ensureStravaDraft(for: workout) }
        .onChange(of: stravaIncludeDurationInDescription) { _, _ in
            guard stravaDraftWorkoutID == workout.id else { return }
            applyStravaDescriptionTemplate(for: workout)
        }
        .onChange(of: stravaIncludeDistanceInDescription) { _, _ in
            guard stravaDraftWorkoutID == workout.id else { return }
            applyStravaDescriptionTemplate(for: workout)
        }
        .onChange(of: stravaIncludeCaloriesInDescription) { _, _ in
            guard stravaDraftWorkoutID == workout.id else { return }
            applyStravaDescriptionTemplate(for: workout)
        }
    }

    // MARK: - Actions

    private func exportWorkout(workout: Workout, format: ExportFormat) {
        do {
            let fileURL = try WorkoutExportService.export(
                workout: workout,
                format: format,
                routeManager: routeManager
            )
            lastExportedFileURL = fileURL
            shareItems = [fileURL]
            showShareSheet = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func openStravaUploader() {
        guard let url = URL(string: "https://www.strava.com/upload/select") else { return }
        openURL(url)
    }

    private func openStravaActivity() {
        guard let activityID = lastUploadedActivityID,
              let url = URL(string: "https://www.strava.com/activities/\(activityID)") else { return }
        openURL(url)
    }

    private func stravaDescriptionOptions() -> StravaPostBuilder.DescriptionOptions {
        StravaPostBuilder.DescriptionOptions(
            includeDuration: stravaIncludeDurationInDescription,
            includeDistance: stravaIncludeDistanceInDescription,
            includeCalories: stravaIncludeCaloriesInDescription
        )
    }

    private func stravaPersonalRecordNames(for workout: Workout) -> [String] {
        let samples = sortedSamples
        guard !samples.isEmpty else { return [] }
        guard let mmp = PersonalRecords.computeMMP(for: samples) else { return [] }
        return PersonalRecords.shared.newPRs(for: mmp).map { "\($0.duration.label) @ \($0.watts)W" }
    }

    private func applyStravaDescriptionTemplate(for workout: Workout) {
        let zoneBuckets = self.zoneBuckets.map { (zone: $0.zone, percent: $0.percent) }
        stravaDescriptionInput = StravaPostBuilder.buildDescription(
            workout: workout,
            routeName: workout.savedRouteName ?? routeManager.routeName,
            totalElevationGain: workout.elevationGain > 0 ? workout.elevationGain : routeManager.totalElevationGain,
            dominantPowerZone: PowerZone.zone(for: Int(workout.avgPower.rounded())),
            zoneBuckets: zoneBuckets,
            personalRecordNames: stravaPersonalRecordNames(for: workout),
            options: stravaDescriptionOptions()
        )
    }

    private func ensureStravaDraft(for workout: Workout) {
        guard stravaDraftWorkoutID != workout.id else { return }
        let prNames = stravaPersonalRecordNames(for: workout)
        stravaTitleInput = StravaPostBuilder.buildTitle(
            workout: workout,
            routeName: workout.savedRouteName ?? routeManager.routeName,
            dominantPowerZone: PowerZone.zone(for: Int(workout.avgPower.rounded())),
            personalRecordNames: prNames
        )
        applyStravaDescriptionTemplate(for: workout)
        stravaDraftWorkoutID = workout.id
    }

    private func uploadToStrava(workout: Workout) {
        Task {
            do {
                guard stravaService.isConnected else {
                    actionError = "Connect your Strava account first."
                    return
                }
                let canExport = WorkoutExportService.canExport(
                    format: selectedExportFormat,
                    hasRoute: routeManager.hasRoute
                )
                guard canExport else {
                    actionError = "Selected format requires a loaded route."
                    return
                }
                let fileURL = try WorkoutExportService.export(
                    workout: workout,
                    format: selectedExportFormat,
                    routeManager: routeManager
                )
                lastExportedFileURL = fileURL
                ensureStravaDraft(for: workout)
                let resolvedTitle = stravaTitleInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedDescription = stravaDescriptionInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let prNames = stravaPersonalRecordNames(for: workout)
                let rideName = resolvedTitle.isEmpty
                    ? StravaPostBuilder.buildTitle(
                        workout: workout,
                        routeName: workout.savedRouteName ?? routeManager.routeName,
                        dominantPowerZone: PowerZone.zone(for: Int(workout.avgPower.rounded())),
                        personalRecordNames: prNames
                    )
                    : resolvedTitle
                let rideDescription = resolvedDescription.isEmpty
                    ? StravaPostBuilder.buildDescription(
                        workout: workout,
                        routeName: workout.savedRouteName ?? routeManager.routeName,
                        totalElevationGain: workout.elevationGain > 0 ? workout.elevationGain : routeManager.totalElevationGain,
                        dominantPowerZone: PowerZone.zone(for: Int(workout.avgPower.rounded())),
                        zoneBuckets: self.zoneBuckets.map { (zone: $0.zone, percent: $0.percent) },
                        personalRecordNames: prNames,
                        options: stravaDescriptionOptions()
                    )
                    : resolvedDescription

                let sportType = uploadAsVirtualRide
                    ? StravaService.SportType.virtualRide
                    : StravaService.SportType.outdoorRide

                let gearID = stravaPreferredGearID.isEmpty ? nil : stravaPreferredGearID

                // Check for duplicate before uploading
                if let existingID = await stravaService.checkForDuplicate(
                    startDate: workout.startDate,
                    elapsedSeconds: Int(workout.duration)
                ) {
                    lastUploadedActivityID = existingID
                    stravaStatus = "Already on Strava — opening activity"
                    // Still update metadata in case the user wants richer description
                    try await stravaService.updateActivity(
                        activityID: existingID,
                        name: rideName,
                        description: rideDescription,
                        sportType: sportType,
                        trainer: uploadAsVirtualRide,
                        commute: commuteStravaUpload,
                        gearID: gearID
                    )
                } else {
                    let stravaExternalID = StravaService.externalIDForWorkout(workoutID: workout.id)
                    let result = try await stravaService.uploadWorkoutFile(
                        fileURL: fileURL,
                        name: rideName,
                        description: rideDescription,
                        trainer: uploadAsVirtualRide,
                        externalID: stravaExternalID,
                        sportType: sportType
                    )
                    if let activityID = result.activityID {
                        lastUploadedActivityID = activityID

                        // PUT after upload so title/description/sport match Mangox (file-derived defaults can win earlier).
                        try await stravaService.updateActivity(
                            activityID: activityID,
                            name: rideName,
                            description: rideDescription,
                            sportType: sportType,
                            trainer: uploadAsVirtualRide,
                            commute: commuteStravaUpload,
                            gearID: gearID
                        )

                        if result.isDuplicateRecovery {
                            stravaStatus = "Strava already had this file — details refreshed."
                        } else {
                            stravaStatus = "Uploaded to Strava! 🎉"
                        }

                        // Attach the summary card photo if opted in
                        if uploadPhotoAfterUpload {
                            let dominantZone = PowerZone.zone(for: Int(workout.avgPower.rounded()))
                            let buckets = self.zoneBuckets.map { (zone: $0.zone, percent: $0.percent) }
                            let samples = self.sortedSamples
                            let mmp = PersonalRecords.computeMMP(for: samples)
                            let prFlags: [NewPRFlag] = mmp.map { PersonalRecords.shared.newPRs(for: $0) } ?? []
                            if let image =  StravaPostBuilder.renderSummaryCard(
                                workout: workout,
                                dominantZone: dominantZone,
                                sortedSamples: samples,
                                mmp: mmp,
                                newPRFlags: prFlags,
                                routeName: workout.savedRouteName ?? routeManager.routeName,
                                totalElevationGain: workout.elevationGain > 0 ? workout.elevationGain : routeManager.totalElevationGain,
                                zoneBuckets: buckets
                            ) {
                                do {
                                    _ = try await stravaService.uploadActivityPhoto(
                                        activityID: activityID,
                                        image: image
                                    )
                                    stravaStatus = result.isDuplicateRecovery
                                        ? "Ride was already on Strava — summary card added."
                                        : "Uploaded to Strava with summary card! 🎉"
                                } catch {
                                    summaryLogger.warning("Photo upload failed (non-fatal): \(error.localizedDescription)")
                                    stravaStatus = result.isDuplicateRecovery
                                        ? "Details updated (photo failed)"
                                        : "Uploaded to Strava! 🎉 (photo failed)"
                                }
                            }
                        }
                    } else {
                        stravaStatus = "Upload queued: \(result.status)"
                    }
                }
            } catch {
                actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Delete & Navigation

    private func deleteWorkout() {
        guard let workout else { return }
        if let dayID = workout.planDayID {
            let planID = workout.planID ?? CachedPlan.shared.id
            DashboardView.unmarkPlanDay(dayID, planID: planID, in: modelContext)
        }
        modelContext.delete(workout)
        do {
            try modelContext.save()
            navigationPath = NavigationPath()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func popFromSummary() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        } else {
            navigationPath = NavigationPath()
        }
    }
}

// MARK: - Summary Content View

private struct SummaryContentView: View {
    let workout: Workout
    let sortedLaps: [LapSplit]
    let zoneBuckets: [ZoneBucket]
    let hrZoneBuckets: [HRZoneBucket]
    let heroAppeared: Bool
    @Binding var showExportModal: Bool
    @Binding var selectedExportFormat: ExportFormat
    let lastExportedFileURL: URL?
    @Environment(StravaService.self) private var stravaService
    @Environment(RouteManager.self) private var routeManager
    let onDone: () -> Void
    let onDelete: () -> Void
    let onOpenStravaUploader: () -> Void

    @Environment(\.isWideSummary) private var isWide

    private var hPad: CGFloat { isWide ? 40 : 20 }
    private var cardGap: CGFloat { isWide ? 16 : 12 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !workout.isValid {
                    SummaryInvalidBanner()
                        .padding(.horizontal, hPad)
                        .padding(.top, 16)
                }

                SummaryHeroHeader(
                    workout: workout,
                    heroAppeared: heroAppeared,
                    onDone: onDone,
                    onDelete: onDelete
                )
                .padding(.horizontal, hPad)
                .padding(.top, isWide ? 28 : 20)

                if isWide {
                    wideBody
                } else {
                    compactBody
                }
            }
            .frame(maxWidth: isWide ? 1100 : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Wide (iPad two-column)

    private var wideBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: cardGap) {
                // LEFT — Metrics (2x2 grid)
                VStack(spacing: cardGap) {
                    metricsGrid
                }
                .frame(maxWidth: .infinity)

                // RIGHT — Zones, Laps
                VStack(spacing: cardGap) {
                    SummaryZoneCard(title: "POWER ZONES", icon: "bolt.fill", buckets: zoneBuckets)
                    if workout.maxHR > 0 {
                        SummaryHRZoneCard(buckets: hrZoneBuckets)
                    }
                    if sortedLaps.count > 1 {
                        SummaryLapTable(laps: sortedLaps, hasHR: workout.avgHR > 0)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, hPad)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: Compact (iPhone single-column)

    private var compactBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: cardGap) {
                SummaryMetricCard(title: "POWER", icon: "bolt.fill") {
                    SummaryPowerMetrics(workout: workout)
                }
                SummaryMetricCard(title: "EFFORT", icon: "flame.fill") {
                    SummaryEffortMetrics(workout: workout)
                }
                if workout.avgHR > 0 {
                    SummaryMetricCard(title: "BODY", icon: "heart.fill") {
                        SummaryBodyMetrics(workout: workout)
                    }
                }
                SummaryMetricCard(title: "MOVEMENT", icon: "figure.indoor.cycle") {
                    SummaryMovementMetrics(workout: workout)
                }
            }
            .padding(.horizontal, hPad)
            .padding(.top, 20)

            SummaryZoneCard(title: "POWER ZONES", icon: "bolt.fill", buckets: zoneBuckets)
                .padding(.horizontal, hPad)
                .padding(.top, 16)

            if workout.maxHR > 0 {
                SummaryHRZoneCard(buckets: hrZoneBuckets)
                    .padding(.horizontal, hPad)
                    .padding(.top, 16)
            }

            if sortedLaps.count > 1 {
                SummaryLapTable(laps: sortedLaps, hasHR: workout.avgHR > 0)
                    .padding(.horizontal, hPad)
                    .padding(.top, 16)
            }

            Spacer().frame(height: 40)
        }
    }

    // MARK: Metrics Grid (iPad 2x2)

    @ViewBuilder
    private var metricsGrid: some View {
        let gap = cardGap
        HStack(spacing: gap) {
            SummaryMetricCard(title: "POWER", icon: "bolt.fill") {
                SummaryPowerMetrics(workout: workout)
            }
            SummaryMetricCard(title: "EFFORT", icon: "flame.fill") {
                SummaryEffortMetrics(workout: workout)
            }
        }
        HStack(spacing: gap) {
            if workout.avgHR > 0 {
                SummaryMetricCard(title: "BODY", icon: "heart.fill") {
                    SummaryBodyMetrics(workout: workout)
                }
            }
            SummaryMetricCard(title: "MOVEMENT", icon: "figure.indoor.cycle") {
                SummaryMovementMetrics(workout: workout)
            }
            if workout.avgHR <= 0 {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Invalid Workout Banner

private struct SummaryInvalidBanner: View {
    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: isWide ? 16 : 14))
                .foregroundStyle(AppColor.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Too Short")
                    .font(.system(size: isWide ? 14 : 12, weight: .bold))
                    .foregroundStyle(AppColor.orange)
                Text("This ride was under 1 minute and won't count toward your training plan.")
                    .font(.system(size: isWide ? 13 : 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(isWide ? 16 : 12)
        .background(AppColor.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(AppColor.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Hero Header (with Done / Delete actions inline)

private struct SummaryHeroHeader: View {
    let workout: Workout
    let heroAppeared: Bool
    let onDone: () -> Void
    let onDelete: () -> Void

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 18 : 14) {
            planDayBadge
            savedOutdoorRouteBadge

            HStack(spacing: 8) {
                Text(workout.startDate, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: isWide ? 17 : 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text("·")
                    .foregroundStyle(.white.opacity(0.15))
                Text(workout.startDate, format: .dateTime.hour().minute())
                    .font(.system(size: isWide ? 17 : 14))
                    .foregroundStyle(.white.opacity(0.35))
            }

            // Duration row with Done ✓ and Delete 🗑 icons
            HStack(alignment: .firstTextBaseline) {
                Text(AppFormat.duration(workout.duration))
                    .font(.system(size: isWide ? 64 : 48, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer()

                // Action buttons at the same vertical level as the duration
                GlassEffectContainer(spacing: isWide ? 14 : 10) {
                    HStack(spacing: isWide ? 14 : 10) {
                        Button(action: onDone) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: isWide ? 22 : 18))
                                .foregroundStyle(AppColor.success)
                                .frame(width: isWide ? 44 : 36, height: isWide ? 44 : 36)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: isWide ? 18 : 14))
                                .foregroundStyle(AppColor.red.opacity(0.7))
                                .frame(width: isWide ? 44 : 36, height: isWide ? 44 : 36)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                    }
                }
                .padding(.bottom, isWide ? 10 : 6)
            }
            .opacity(heroAppeared ? 1 : 0)
            .offset(y: heroAppeared ? 0 : 12)

            heroStatsRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var savedOutdoorRouteBadge: some View {
        if let raw = workout.savedRouteKindRaw, let kind = SavedRouteKind(rawValue: raw) {
            let title: String = {
                switch kind {
                case .free:
                    return "Outdoor · Free ride"
                case .gpx:
                    let n = workout.savedRouteName ?? "GPX"
                    return "GPX · \(n)"
                case .directions:
                    let n = workout.savedRouteName ?? "Route"
                    if let sub = workout.routeDestinationSummary, !sub.isEmpty {
                        return "Directions · \(n) — \(sub)"
                    }
                    return "Directions · \(n)"
                }
            }()
            HStack(spacing: 6) {
                Image(systemName: "map")
                    .font(.system(size: isWide ? 12 : 10))
                Text(title)
                    .font(.system(size: isWide ? 13 : 11, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(AppColor.blue)
            .padding(.horizontal, isWide ? 16 : 12)
            .padding(.vertical, isWide ? 7 : 5)
            .background(AppColor.blue.opacity(0.1))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var planDayBadge: some View {
        if let dayID = workout.planDayID {
            let plan = PlanLibrary.resolvePlan(planID: workout.planID) ?? CachedPlan.shared
            if let day = plan.day(id: dayID) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: isWide ? 12 : 10))
                    Text("W\(day.weekNumber)D\(day.dayOfWeek) · \(day.title)")
                        .font(.system(size: isWide ? 13 : 11, weight: .semibold))
                }
                .foregroundStyle(AppColor.yellow)
                .padding(.horizontal, isWide ? 16 : 12)
                .padding(.vertical, isWide ? 7 : 5)
                .background(AppColor.yellow.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }

    private var heroStatsRow: some View {
        HStack(spacing: 0) {
            heroStat(value: String(format: "%.1f", workout.distance / 1000), unit: "km", icon: "road.lanes")
            Spacer()
            heroStat(value: String(format: "%.0f", estimateCalories), unit: "kcal", icon: "flame.fill")
            Spacer()
            heroStat(value: "\(Int(workout.avgPower))", unit: "W", icon: "bolt.fill")
            if workout.avgHR > 0 {
                Spacer()
                heroStat(value: "\(Int(workout.avgHR))", unit: "bpm", icon: "heart.fill")
            }
        }
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : 8)
    }

    private func heroStat(value: String, unit: String, icon: String) -> some View {
        VStack(spacing: isWide ? 5 : 3) {
            Image(systemName: icon)
                .font(.system(size: isWide ? 13 : 10))
                .foregroundStyle(.white.opacity(0.25))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: isWide ? 22 : 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Text(unit)
                    .font(.system(size: isWide ? 11 : 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private var estimateCalories: Double {
        Double(WorkoutExportService.estimateCalories(avgPower: workout.avgPower, durationSeconds: workout.duration))
    }
}

// MARK: - Section Header

private struct SummarySectionHeader: View {
    let title: String
    let icon: String

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        HStack(spacing: isWide ? 8 : 6) {
            Image(systemName: icon)
                .font(.system(size: isWide ? 12 : 10))
                .foregroundStyle(.white.opacity(0.3))
            Text(title)
                .font(.system(size: isWide ? 11 : 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.5)
        }
    }
}

// MARK: - Metric Card Container

private struct SummaryMetricCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 14 : 12) {
            SummarySectionHeader(title: title, icon: icon)
            content
            Spacer(minLength: 0)
        }
        .padding(isWide ? 20 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: isWide ? 20 : 16)
    }
}

// MARK: - Metric Value Primitives

private struct MetricValueView: View {
    let value: String
    let unit: String
    let color: Color
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
    }
}

private struct MetricCellView: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 5 : 4) {
            Text(label)
                .font(.system(size: isWide ? 10 : 8, weight: .heavy))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            MetricValueView(value: value, unit: unit, color: color, size: isWide ? 22 : 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Power Metrics

private struct SummaryPowerMetrics: View {
    let workout: Workout

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        let avgZone = PowerZone.zone(for: Int(workout.avgPower))
        let maxZone = PowerZone.zone(for: workout.maxPower)
        let primarySize: CGFloat = isWide ? 34 : 28

        VStack(spacing: isWide ? 14 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MetricValueView(value: "\(Int(workout.avgPower))", unit: "W", color: avgZone.color, size: primarySize)
                Text(avgZone.name)
                    .font(.system(size: isWide ? 13 : 11, weight: .semibold))
                    .foregroundStyle(avgZone.color.opacity(0.7))
                    .lineLimit(1)
                    .padding(.horizontal, isWide ? 10 : 8)
                    .padding(.vertical, isWide ? 4 : 3)
                    .background(avgZone.color.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }

            HStack(spacing: 0) {
                MetricCellView(label: "MAX", value: "\(workout.maxPower)", unit: "W", color: maxZone.color)
                Spacer()
                MetricCellView(label: "NP", value: "\(Int(workout.normalizedPower))", unit: "W", color: AppColor.yellow)
                Spacer()
                MetricCellView(label: "ZONE", value: "Z\(avgZone.id)", unit: "", color: avgZone.color)
            }
        }
    }
}

// MARK: - Effort Metrics

private struct SummaryEffortMetrics: View {
    let workout: Workout

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        let ifColor = intensityColor(workout.intensityFactor)
        let tColor = tssColor(workout.tss)
        let primarySize: CGFloat = isWide ? 34 : 28
        let vi = workout.avgPower > 0 ? workout.normalizedPower / workout.avgPower : 0

        VStack(spacing: isWide ? 14 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MetricValueView(value: String(format: "%.0f", workout.tss), unit: "TSS", color: tColor, size: primarySize)
                Spacer()
            }

            HStack(spacing: 0) {
                MetricCellView(label: "IF", value: String(format: "%.2f", workout.intensityFactor), unit: "", color: ifColor)
                Spacer()
                MetricCellView(label: "KCAL", value: String(format: "%.0f", estimateCalories), unit: "", color: AppColor.orange)
                Spacer()
                MetricCellView(label: "VI", value: String(format: "%.2f", vi), unit: "", color: .white.opacity(0.7))
            }
        }
    }

    private var estimateCalories: Double {
        Double(WorkoutExportService.estimateCalories(avgPower: workout.avgPower, durationSeconds: workout.duration))
    }

    private func intensityColor(_ ifValue: Double) -> Color {
        if ifValue < 0.75 { return AppColor.success }
        if ifValue < 0.90 { return AppColor.yellow }
        if ifValue < 1.05 { return AppColor.orange }
        return AppColor.red
    }

    private func tssColor(_ tss: Double) -> Color {
        if tss < 150 { return AppColor.success }
        if tss < 300 { return AppColor.yellow }
        if tss < 450 { return AppColor.orange }
        return AppColor.red
    }
}

// MARK: - Body Metrics

private struct SummaryBodyMetrics: View {
    let workout: Workout

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        let hrZone = HeartRateZone.zone(for: Int(workout.avgHR))
        let primarySize: CGFloat = isWide ? 34 : 28

        VStack(spacing: isWide ? 14 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MetricValueView(value: "\(Int(workout.avgHR))", unit: "bpm", color: AppColor.heartRate, size: primarySize)
                Text(hrZone.name)
                    .font(.system(size: isWide ? 13 : 11, weight: .semibold))
                    .foregroundStyle(hrZone.color.opacity(0.7))
                    .lineLimit(1)
                    .padding(.horizontal, isWide ? 10 : 8)
                    .padding(.vertical, isWide ? 4 : 3)
                    .background(hrZone.color.opacity(0.1))
                    .clipShape(Capsule())
                Spacer()
            }

            HStack(spacing: 0) {
                MetricCellView(label: "MAX HR", value: "\(workout.maxHR)", unit: "bpm", color: AppColor.red)
                Spacer()
                MetricCellView(label: "HR ZONE", value: "Z\(hrZone.id)", unit: "", color: hrZone.color)
                Spacer()
                MetricCellView(label: "RANGE", value: "\(workout.maxHR - Int(workout.avgHR))", unit: "Δ", color: .white.opacity(0.5))
            }
        }
    }
}

// MARK: - Movement Metrics

private struct SummaryMovementMetrics: View {
    let workout: Workout

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        let primarySize: CGFloat = isWide ? 34 : 28

        VStack(spacing: isWide ? 14 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                MetricValueView(
                    value: String(format: "%.1f", workout.distance / 1000),
                    unit: "km",
                    color: .white.opacity(0.85),
                    size: primarySize
                )
                Spacer()

                // Elevation gain — only shown when a GPX route with <ele> data was ridden.
                if workout.elevationGain > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: isWide ? 10 : 8))
                                .foregroundStyle(AppColor.success.opacity(0.8))
                            Text("+\(Int(workout.elevationGain.rounded())) m")
                                .font(.system(size: isWide ? 16 : 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppColor.success)
                        }
                        Text("elevation")
                            .font(.system(size: isWide ? 9 : 8))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }

            HStack(spacing: 0) {
                MetricCellView(label: "CADENCE", value: "\(Int(workout.avgCadence))", unit: "rpm", color: AppColor.blue)
                Spacer()
                MetricCellView(label: "SPEED", value: String(format: "%.1f", workout.avgSpeed), unit: "km/h", color: .white.opacity(0.7))
            }
        }
    }
}

// MARK: - Zone Row

private struct ZoneRowView: View {
    let zoneLabel: String
    let zoneName: String
    let percent: Double
    let color: Color
    let seconds: Int

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        HStack(spacing: isWide ? 12 : 10) {
            Text(zoneLabel)
                .font(.system(size: isWide ? 12 : 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: isWide ? 28 : 22, alignment: .leading)

            Text(zoneName)
                .font(.system(size: isWide ? 12 : 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: isWide ? 90 : 65, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.04))
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, geo.size.width * percent))
                }
            }
            .frame(height: isWide ? 14 : 10)

            Text("\(Int(percent * 100))%")
                .font(.system(size: isWide ? 13 : 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: isWide ? 42 : 34, alignment: .trailing)

            Text(AppFormat.seconds(seconds))
                .font(.system(size: isWide ? 11 : 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: isWide ? 56 : 42, alignment: .trailing)
        }
    }
}

// MARK: - Power Zone Distribution Card

private struct SummaryZoneCard: View {
    let title: String
    let icon: String
    let buckets: [ZoneBucket]

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 14 : 12) {
            SummarySectionHeader(title: title, icon: icon)

            VStack(spacing: isWide ? 10 : 8) {
                ForEach(buckets) { bucket in
                    ZoneRowView(
                        zoneLabel: "Z\(bucket.zone.id)",
                        zoneName: bucket.zone.name,
                        percent: bucket.percent,
                        color: bucket.zone.color,
                        seconds: bucket.seconds
                    )
                }
            }
        }
        .padding(isWide ? 20 : 14)
        .cardStyle(cornerRadius: isWide ? 20 : 16)
    }
}

// MARK: - HR Zone Distribution Card

private struct SummaryHRZoneCard: View {
    let buckets: [HRZoneBucket]

    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 14 : 12) {
            HStack {
                SummarySectionHeader(title: "HEART RATE ZONES", icon: "heart.fill")
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Max: \(HeartRateZone.maxHR) bpm")
                        .font(.system(size: isWide ? 10 : 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                    if HeartRateZone.hasRestingHR {
                        Text("Rest: \(HeartRateZone.restingHR) bpm")
                            .font(.system(size: isWide ? 10 : 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }

            VStack(spacing: isWide ? 10 : 8) {
                ForEach(buckets) { bucket in
                    ZoneRowView(
                        zoneLabel: "Z\(bucket.zone.id)",
                        zoneName: bucket.zone.name,
                        percent: bucket.percent,
                        color: bucket.zone.color,
                        seconds: bucket.seconds
                    )
                }
            }
        }
        .padding(isWide ? 20 : 14)
        .cardStyle(cornerRadius: isWide ? 20 : 16)
    }
}

// MARK: - Lap Table

private struct SummaryLapTable: View {
    let laps: [LapSplit]
    let hasHR: Bool

    @Environment(\.isWideSummary) private var isWide

    private var colNum: CGFloat { isWide ? 36 : 22 }
    private var colDur: CGFloat { isWide ? 90 : 62 }
    private var colAvg: CGFloat { isWide ? 80 : 52 }
    private var colMax: CGFloat { isWide ? 80 : 52 }
    private var colHR: CGFloat { hasHR ? (isWide ? 68 : 44) : 0 }
    private var colDist: CGFloat { isWide ? 72 : 46 }
    private var colCad: CGFloat { isWide ? 72 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 14 : 12) {
            SummarySectionHeader(title: "LAPS", icon: "flag.fill")

            headerRow

            ForEach(laps) { lap in
                lapRow(lap)
            }
        }
        .padding(isWide ? 20 : 14)
        .cardStyle(cornerRadius: isWide ? 20 : 16)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            lapText("#", width: colNum, alignment: .leading, isHeader: true)
            lapText("Duration", width: colDur, alignment: .leading, isHeader: true)
            lapText("Avg Pwr", width: colAvg, alignment: .trailing, isHeader: true)
            lapText("Max Pwr", width: colMax, alignment: .trailing, isHeader: true)
            if hasHR {
                lapText("Avg HR", width: colHR, alignment: .trailing, isHeader: true)
            }
            lapText("Dist", width: colDist, alignment: .trailing, isHeader: true)
            if isWide {
                lapText("Cadence", width: colCad, alignment: .trailing, isHeader: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func lapRow(_ lap: LapSplit) -> some View {
        let lapZone = PowerZone.zone(for: Int(lap.avgPower))

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                lapText("\(lap.lapNumber)", width: colNum, alignment: .leading, isHeader: false)
                lapText(AppFormat.duration(lap.duration), width: colDur, alignment: .leading, isHeader: false)
                Text("\(Int(lap.avgPower))W")
                    .font(.system(size: isWide ? 13 : 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lapZone.color)
                    .frame(width: colAvg, alignment: .trailing)
                lapText("\(lap.maxPower)W", width: colMax, alignment: .trailing, isHeader: false)
                if hasHR {
                    lapText(lap.avgHR > 0 ? "\(Int(lap.avgHR))" : "—", width: colHR, alignment: .trailing, isHeader: false)
                }
                lapText(String(format: "%.2fkm", lap.distance / 1000), width: colDist, alignment: .trailing, isHeader: false)
                if isWide {
                    lapText(lap.avgCadence > 0 ? "\(Int(lap.avgCadence))" : "—", width: colCad, alignment: .trailing, isHeader: false)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, isWide ? 5 : 3)

            if lap.lapNumber < laps.count {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 1)
            }
        }
    }

    private func lapText(_ text: String, width: CGFloat, alignment: Alignment, isHeader: Bool) -> some View {
        Text(text)
            .font(.system(size: isHeader ? (isWide ? 10 : 9) : (isWide ? 13 : 11), weight: isHeader ? .bold : .regular, design: .monospaced))
            .foregroundStyle(isHeader ? .white.opacity(0.3) : .white.opacity(0.75))
            .frame(width: width, alignment: alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Export Sheet Content (modal)

private struct ExportSheetContent: View {
    let workout: Workout
    @Binding var selectedExportFormat: ExportFormat
    @Environment(RouteManager.self) private var routeManager
    let lastExportedFileURL: URL?
    let onExport: (ExportFormat) -> Void
    let onOpenStravaUploader: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Format selector
            Text("FORMAT")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(1)

            HStack(spacing: 10) {
                ForEach(ExportFormat.allCases) { format in
                    formatButton(for: format)
                }
            }

            // Format description
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text(selectedExportFormat.subtitle)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.3))

            // Export button
            exportActionButton

            // Strava web uploader link
            if lastExportedFileURL != nil {
                Button(action: onOpenStravaUploader) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 12))
                        Text("Open Strava Web Uploader")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(AppColor.mango.opacity(0.7))
                }
            }
        }
    }

    private func formatButton(for format: ExportFormat) -> some View {
        let canExport = WorkoutExportService.canExport(format: format, hasRoute: routeManager.hasRoute)
        let isSelected = selectedExportFormat == format
        let titleColor: Color = isSelected ? .white : (canExport ? .white.opacity(0.5) : .white.opacity(0.2))
        let subtitleColor: Color = isSelected ? .white.opacity(0.5) : .white.opacity(0.2)
        let bgColor: Color = isSelected ? AppColor.orange.opacity(0.12) : Color.white.opacity(0.02)
        let borderColor: Color = isSelected ? AppColor.orange.opacity(0.3) : Color.white.opacity(0.05)
        let subtitleText: String = format == .tcx ? "Indoor" : (routeManager.hasRoute ? "Route loaded" : "Needs route")

        return Button { selectedExportFormat = format } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: format == .tcx ? "doc.text" : "map")
                        .font(.system(size: 11))
                    Text(format.rawValue)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(titleColor)

                Text(subtitleText)
                    .font(.system(size: 9))
                    .foregroundStyle(subtitleColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .disabled(!canExport)
        .opacity(canExport ? 1.0 : 0.5)
    }

    private var exportActionButton: some View {
        let canExportSelected = WorkoutExportService.canExport(format: selectedExportFormat, hasRoute: routeManager.hasRoute)
        let fgColor: Color = canExportSelected ? .white : .white.opacity(0.3)
        let bgOpacity: Double = canExportSelected ? 0.12 : 0.04
        let borderOpacity: Double = canExportSelected ? 0.3 : 0.1

        return Button { onExport(selectedExportFormat) } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                Text("Export \(selectedExportFormat.rawValue)")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(fgColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColor.orange.opacity(bgOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppColor.orange.opacity(borderOpacity), lineWidth: 1)
            )
        }
        .disabled(!canExportSelected)
    }
}

// MARK: - Strava Sheet Content

private struct StravaSheetContentView: View {
    let workout: Workout
    @Environment(StravaService.self) private var stravaService
    @Binding var stravaTitleInput: String
    @Binding var stravaDescriptionInput: String
    @Binding var includeDurationInDescription: Bool
    @Binding var includeDistanceInDescription: Bool
    @Binding var includeCaloriesInDescription: Bool
    @Binding var commuteStravaUpload: Bool
    @Binding var preferredGearID: String
    @Binding var uploadAsVirtualRide: Bool
    @Binding var uploadPhotoAfterUpload: Bool
    @Binding var showDescriptionPreview: Bool
    let stravaStatus: String?
    let lastUploadedActivityID: Int?
    let onResetDescriptionTemplate: () -> Void
    let onUpload: () -> Void
    let onOpenActivity: () -> Void

    @State private var stravaBikes: [StravaService.AthleteBike] = []
    @State private var stravaBikesLoading = false
    @State private var stravaBikesLoadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !stravaService.isConnected {
                notConnectedView
            } else {
                connectedForm
            }
        }
        .task(id: stravaService.isConnected) {
            guard stravaService.isConnected else {
                stravaBikes = []
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
    }

    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.orange)
            Text("Connect Strava from Home to upload rides.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var descriptionFieldBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("DESCRIPTION")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1)
                Spacer(minLength: 8)
                Button("Reset template", action: onResetDescriptionTemplate)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.mango.opacity(0.85))
                    .accessibilityLabel("Reset description to generated template")
            }

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $stravaDescriptionInput)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Activity description")
                    .accessibilityHint("Plain text sent to Strava. Edit freely before uploading.")

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDescriptionPreview.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showDescriptionPreview ? "eye.slash" : "eye")
                            .font(.system(size: 10))
                        Text(showDescriptionPreview ? "Hide preview" : "Preview on Strava")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(AppColor.mango.opacity(0.7))
                }

                if showDescriptionPreview {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("HOW IT LOOKS ON STRAVA")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.2))
                            .tracking(1.5)
                            .padding(.bottom, 8)

                        ScrollView {
                            Text(stravaDescriptionInput.isEmpty ? "No description" : stravaDescriptionInput)
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 72, maxHeight: 220)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private var bikeAndCommuteBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $commuteStravaUpload) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mark as commute")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("Sets Strava’s commute flag on this activity.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .toggleStyle(.switch)
            .tint(AppColor.mango)

            VStack(alignment: .leading, spacing: 6) {
                Text("BIKE (STRAVA GEAR)")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1)

                if stravaBikesLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("Loading bikes…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                } else if stravaBikesLoadFailed {
                    Text("Could not load bikes. Disconnect and connect Strava again to grant profile access.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                } else if stravaBikes.isEmpty {
                    Text("No bikes on your Strava profile. Add a bike on strava.com to link activities.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    Picker("Bike", selection: $preferredGearID) {
                        Text("None").tag("")
                        ForEach(stravaBikes) { bike in
                            Text(bike.name).tag(bike.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColor.mango)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var connectedForm: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppColor.success)
                .frame(width: 6, height: 6)
            Text(stravaService.athleteDisplayName ?? "Connected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }

        fieldBlock(label: "TITLE") {
            TextField("Activity title", text: $stravaTitleInput)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Activity title")
        }

        Toggle(isOn: $includeDurationInDescription) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include duration in description")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Strava still shows ride time on the activity. Turn off to shorten the text.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .toggleStyle(.switch)
        .tint(AppColor.mango)
        .accessibilityHint("Regenerates the description template from your ride data.")

        Toggle(isOn: $includeDistanceInDescription) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include distance in description")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Strava already shows distance on the activity header.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .toggleStyle(.switch)
        .tint(AppColor.mango)

        Toggle(isOn: $includeCaloriesInDescription) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include calories in description")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Estimated from power; turn off to shorten the preview.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .toggleStyle(.switch)
        .tint(AppColor.mango)

        descriptionFieldBlock

        bikeAndCommuteBlock

        VStack(spacing: 10) {
            Toggle(isOn: $uploadAsVirtualRide) {
                HStack(spacing: 6) {
                    Image(systemName: uploadAsVirtualRide ? "bicycle" : "figure.outdoor.cycle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(uploadAsVirtualRide ? "Virtual Ride" : "Outdoor Ride")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toggleStyle(.switch)
            .tint(AppColor.mango)

            Toggle(isOn: $uploadPhotoAfterUpload) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(uploadPhotoAfterUpload ? AppColor.mango.opacity(0.7) : .white.opacity(0.3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Attach summary card")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("Posts a visual stats card as activity photo")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(AppColor.mango)
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        uploadButton
        statusMessages
    }

    private func fieldBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(1)
            content()
        }
    }

    private var uploadButton: some View {
        Button(action: onUpload) {
            HStack(spacing: 8) {
                if stravaService.isBusy {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                }
                Text(stravaService.isBusy ? "Uploading…" : "Upload to Strava")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [AppColor.strava, AppColor.stravaEnd],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(stravaService.isBusy)
        .opacity(stravaService.isBusy ? 0.7 : 1)
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let stravaStatus {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.success)
                Text(stravaStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let err = stravaService.lastError, !err.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.orange)
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.orange.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if lastUploadedActivityID != nil {
            Button(action: onOpenActivity) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12))
                    Text("View on Strava")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(AppColor.mango)
            }
        }
    }
}

// MARK: - Supporting Types

private struct ZoneBucket: Identifiable {
    let zone: PowerZone
    let seconds: Int
    let percent: Double
    var id: Int { zone.id }
}

private struct HRZoneBucket: Identifiable {
    let zone: HeartRateZone
    let seconds: Int
    let percent: Double
    var id: Int { zone.id }
}

// MARK: - Preview

#Preview {
    SummaryView(
        workoutID: UUID(),
        navigationPath: .constant(NavigationPath())
    )
    .modelContainer(for: [Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self], inMemory: true)
}

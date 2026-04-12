import SwiftData
import SwiftUI
import UIKit
import os.log

private let summaryLogger = Logger(subsystem: "com.abchalita.Mangox", category: "SummaryView")

private enum SummaryRiderNaming {
    /// First token of Strava display name for on-device insight headlines (optional).
    static func stravaFirstName(from displayName: String?) -> String? {
        guard let raw = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }
        let token =
            raw.split { $0.isWhitespace || $0 == "·" }
            .first
            .map(String.init) ?? raw
        if token.count > 24 { return String(token.prefix(24)) }
        return token
    }
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
    @State private var viewModel: WorkoutViewModel
    @Binding var navigationPath: NavigationPath

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [Workout]

    /// When false, generated Strava description omits the duration line (Strava still shows elapsed time on the activity).
    @AppStorage("stravaUploadDescriptionIncludeDuration") private
        var stravaIncludeDurationInDescription = true
    @AppStorage("stravaUploadDescriptionIncludeDistance") private
        var stravaIncludeDistanceInDescription = true
    @AppStorage("stravaUploadDescriptionIncludeCalories") private
        var stravaIncludeCaloriesInDescription = true
    @AppStorage("stravaUploadPreferredGearID") private var stravaPreferredGearID = ""
    @State private var heroAppeared = false
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var isWide: Bool { hSizeClass != .compact }

    private let bg = AppColor.bg
    /// Toolbar size for third-party brand marks (Instagram, Strava) — matches typical bar button metrics.
    private let toolbarBrandIconSize: CGFloat = 22

    init(
        workoutID: UUID,
        navigationPath: Binding<NavigationPath>,
        viewModel: WorkoutViewModel
    ) {
        self.workoutID = workoutID
        self._navigationPath = navigationPath
        self._viewModel = State(initialValue: viewModel)
        let id = workoutID
        self._workouts = Query(
            filter: #Predicate<Workout> { workout in
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

    private var sortedSamples: [WorkoutSampleData] {
        viewModel.sortedSamples
    }

    private var sortedLaps: [LapSplit] {
        viewModel.sortedLaps
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
            lastSampleElapsed: workout.samples.last?.elapsedSeconds ?? 0,
            lastLapNumber: workout.laps.count
        )
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<WorkoutViewModel, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private var stravaButtonLabel: some View {
        if viewModel.isStravaBusy {
            ProgressView()
                .tint(.white)
        } else if viewModel.lastUploadedActivityID != nil {
            Image(systemName: "checkmark.circle.fill")
        } else {
            Image("BrandStrava")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: toolbarBrandIconSize, height: toolbarBrandIconSize)
                .accessibilityHidden(true)
        }
    }

    private var stravaButtonTint: Color {
        if viewModel.lastUploadedActivityID != nil {
            return AppColor.success
        } else if viewModel.isStravaConnected {
            return .white
        } else {
            return AppColor.orange
        }
    }

    private var stravaToolbarButton: some View {
        Button {
            if viewModel.lastUploadedActivityID != nil {
                viewModel.requestOpenUploadedStravaActivity()
            } else {
                viewModel.presentStravaSheet()
            }
        } label: {
            stravaButtonLabel
        }
        .disabled(viewModel.isStravaBusy)
        .tint(stravaButtonTint)
        .accessibilityLabel(stravaToolbarAccessibilityLabel)
    }

    private var stravaToolbarAccessibilityLabel: String {
        if viewModel.isStravaBusy {
            return "Uploading to Strava"
        }
        if viewModel.lastUploadedActivityID != nil {
            return "Open in Strava"
        }
        return "Upload to Strava"
    }

    private func resetPreparedSummary(resetHero: Bool = false) {
        viewModel.invalidatePreparedSummaryData()
        viewModel.clearStravaDraft()
        if resetHero {
            heroAppeared = false
        }
    }

    private func prepareSummaryData(force: Bool = false) async {
        guard workout != nil else {
            resetPreparedSummary(resetHero: true)
            return
        }
        await viewModel.prepareSummaryData(
            workout: workout,
            signature: workoutDataSignature,
            force: force
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if let workout {
                if viewModel.isSummaryDataReady {
                    SummaryContentView(
                        workout: workout,
                        linkedPlanDay: viewModel.resolvePlanDay(
                            planID: workout.planID,
                            dayID: workout.planDayID
                        ),
                        sortedLaps: sortedLaps,
                        zoneBuckets: zoneBuckets,
                        hrZoneBuckets: hrZoneBuckets,
                        dominantZone: dominantZone,
                        heroAppeared: heroAppeared,
                        showExportModal: binding(\.showExportModal),
                        selectedExportFormat: binding(\.selectedExportFormat),
                        lastExportedFileURL: viewModel.lastExportedFileURL,
                        stravaAthleteDisplayName: viewModel.stravaAthleteDisplayName,
                        syncWorkoutsToAppleHealth: viewModel.syncWorkoutsToAppleHealth,
                        workoutSyncToHealthLastError: viewModel.workoutSyncToHealthLastError,
                        onDone: popFromSummary,
                        onDelete: promptDeleteWorkout,
                        onOpenStravaUploader: viewModel.requestOpenStravaUploader,
                        onRepeatStructuredWorkout: repeatStructuredWorkout,
                        customRepeatTemplateID: viewModel.customRepeatTemplateID,
                        onSaveAsCustomWorkout: saveWorkoutAsCustomTemplate,
                        onRepeatSavedCustomWorkout: repeatSavedCustomWorkout
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
            if viewModel.isStravaConfigured {
                ToolbarItem(placement: .topBarTrailing) {
                    stravaToolbarButton
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard workout != nil, viewModel.isSummaryDataReady else { return }
                    viewModel.presentInstagramStoryStudio()
                } label: {
                    Image("BrandInstagram")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: toolbarBrandIconSize, height: toolbarBrandIconSize)
                        .accessibilityHidden(true)
                }
                .disabled(!viewModel.isSummaryDataReady)
                .tint(
                    Color(
                        red: 0.88,
                        green: 0.19,
                        blue: 0.42
                    )
                )
                .accessibilityLabel("Instagram Story — customize and share")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showExportModal = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: binding(\.showInstagramStoryStudio)) {
            if let workout, viewModel.isSummaryDataReady {
                InstagramStoryStudioView(
                    workout: workout,
                    routeName: workout.savedRouteName ?? viewModel.routeName,
                    totalElevationGain: workout.elevationGain > 0
                        ? workout.elevationGain : viewModel.totalElevationGain,
                    personalRecordNames: stravaPersonalRecordNames(for: workout),
                    onDismiss: { viewModel.dismissInstagramStoryStudio() },
                    onShareError: { message in
                        viewModel.dismissInstagramStoryStudio()
                        viewModel.presentError(message)
                    },
                    viewModel: SocialViewModel()
                )
            }
        }
        .sheet(isPresented: binding(\.showShareSheet)) {
            ShareSheet(activityItems: viewModel.shareItems)
        }
        .confirmationDialog(
            "Summary image",
            isPresented: binding(\.showStravaPhotoFallbackDialog),
            titleVisibility: .visible
        ) {
            Button("Share image") {
                if let img = viewModel.stravaPhotoFallbackImage {
                    viewModel.presentShareItems([img])
                }
                viewModel.clearStravaPhotoFallback()
            }
            Button("Not now", role: .cancel) {
                viewModel.clearStravaPhotoFallback()
            }
        } message: {
            Text(
                "Strava doesn’t allow third-party apps to attach photos to activities automatically. "
                    + "Share this image to save it to Photos or add it from the Strava app."
            )
        }
        .sheet(isPresented: binding(\.showExportModal)) {
            if let workout {
                exportSheet(for: workout)
            }
        }
        .sheet(isPresented: binding(\.showStravaCard)) {
            if let workout {
                stravaSheet(for: workout)
            }
        }
        .alert("Delete Ride?", isPresented: binding(\.showDeleteConfirmation)) {
            Button("Delete", role: .destructive) { deleteWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This ride and all recorded data will be permanently removed. If this was a training plan workout, it will be un-marked as completed."
            )
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .task {
            await prepareSummaryData()
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                heroAppeared = true
            }
        }
        .onChange(of: workoutDataSignature) { _, newSignature in
            guard newSignature != nil else {
                resetPreparedSummary(resetHero: true)
                return
            }
            Task { await prepareSummaryData(force: true) }
        }
        .onChange(of: workouts) { _, newWorkouts in
            // After deletion the filtered @Query is empty — drop cached graphs so we never
            // flash stale content if the view is reused or navigation is odd.
            if newWorkouts.isEmpty {
                resetPreparedSummary(resetHero: true)
            }
        }
        .onChange(of: viewModel.pendingExternalNavigation) { _, request in
            guard let request else { return }
            openURL(request.url)
            viewModel.clearPendingExternalNavigation()
        }
        .environment(viewModel)
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
        viewModel.zoneBuckets
    }

    private var hrZoneBuckets: [HRZoneBucket] {
        viewModel.hrZoneBuckets
    }

    // MARK: - Export Sheet

    private func exportSheet(for workout: Workout) -> some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    ExportSheetContent(
                        workout: workout,
                        selectedExportFormat: binding(\.selectedExportFormat),
                        hasRoute: viewModel.hasRoute,
                        lastExportedFileURL: viewModel.lastExportedFileURL,
                        onExport: { fmt in
                            exportWorkout(workout: workout, format: fmt)
                            viewModel.showExportModal = false
                        },
                        onOpenStravaUploader: { viewModel.requestOpenStravaUploader() }
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
                    Button("Close") { viewModel.showExportModal = false }
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
                        stravaTitleInput: binding(\.stravaTitleInput),
                        stravaDescriptionInput: binding(\.stravaDescriptionInput),
                        includeDurationInDescription: $stravaIncludeDurationInDescription,
                        includeDistanceInDescription: $stravaIncludeDistanceInDescription,
                        includeCaloriesInDescription: $stravaIncludeCaloriesInDescription,
                        commuteStravaUpload: binding(\.commuteStravaUpload),
                        preferredGearID: $stravaPreferredGearID,
                        uploadAsVirtualRide: binding(\.uploadAsVirtualRide),
                        uploadPhotoAfterUpload: binding(\.uploadPhotoAfterUpload),
                        showDescriptionPreview: binding(\.showDescriptionPreview),
                        stravaStatus: viewModel.stravaStatus,
                        lastUploadedActivityID: viewModel.lastUploadedActivityID,
                        onResetDescriptionTemplate: {
                            applyStravaDescriptionTemplate(for: workout)
                        },
                        onUpload: { uploadToStrava(workout: workout) },
                        onOpenActivity: { viewModel.requestOpenUploadedStravaActivity() }
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
                    Button("Close") { viewModel.dismissStravaSheet() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { ensureStravaDraft(for: workout) }
        .onChange(of: stravaIncludeDurationInDescription) { _, _ in
            guard viewModel.stravaDraftWorkoutID == workout.id else { return }
            applyStravaDescriptionTemplate(for: workout)
        }
        .onChange(of: stravaIncludeDistanceInDescription) { _, _ in
            guard viewModel.stravaDraftWorkoutID == workout.id else { return }
            applyStravaDescriptionTemplate(for: workout)
        }
        .onChange(of: stravaIncludeCaloriesInDescription) { _, _ in
            guard viewModel.stravaDraftWorkoutID == workout.id else { return }
            applyStravaDescriptionTemplate(for: workout)
        }
    }

    // MARK: - Actions

    private func exportWorkout(workout: Workout, format: ExportFormat) {
        viewModel.exportWorkout(workout: workout, format: format)
    }

    private func stravaDescriptionOptions() -> StravaDescriptionTemplateOptions {
        StravaDescriptionTemplateOptions(
            includeDuration: stravaIncludeDurationInDescription,
            includeDistance: stravaIncludeDistanceInDescription,
            includeCalories: stravaIncludeCaloriesInDescription
        )
    }

    private func stravaTemplateInput(for workout: Workout) -> StravaDescriptionTemplateInput {
        StravaDescriptionTemplateInput(
            routeName: workout.savedRouteName ?? viewModel.routeName,
            totalElevationGain: workout.elevationGain > 0
                ? workout.elevationGain : viewModel.totalElevationGain,
            dominantPowerZone: PowerZone.zone(for: Int(workout.avgPower.rounded())),
            zoneBuckets: zoneBuckets.map { (zone: $0.zone, percent: $0.percent) },
            personalRecordNames: stravaPersonalRecordNames(for: workout),
            options: stravaDescriptionOptions()
        )
    }

    private func stravaPersonalRecordNames(for workout: Workout) -> [String] {
        let samples = sortedSamples
        guard !samples.isEmpty else { return [] }
        guard let mmp = viewModel.computeMMP(for: samples, workoutID: workout.id) else {
            return []
        }
        return viewModel.newPRs(for: mmp).map { "\($0.duration.label) @ \($0.watts)W" }
    }

    private func applyStravaDescriptionTemplate(for workout: Workout) {
        viewModel.applyStravaDescriptionTemplate(
            for: workout,
            template: stravaTemplateInput(for: workout)
        )
    }

    private func ensureStravaDraft(for workout: Workout) {
        viewModel.ensureStravaDraft(for: workout, template: stravaTemplateInput(for: workout))
    }

    /// Uploads the summary card JPEG when **Attach summary card** is on. Used after a fresh Strava upload
    /// and when an existing activity is matched (duplicate check) so both paths get a photo.
    private func uploadStravaSummaryCardPhoto(
        activityID: Int,
        workout: Workout,
        duplicateRecovery: Bool
    ) async {
        guard viewModel.uploadPhotoAfterUpload else { return }

        let dominantZone = PowerZone.zone(for: Int(workout.avgPower.rounded()))
        let buckets = zoneBuckets.map { (zone: $0.zone, percent: $0.percent) }
        let samples = sortedSamples
        let mmp = viewModel.computeMMP(for: samples, workoutID: workout.id)
        let prFlags: [NewPRFlag] = mmp.map { viewModel.newPRs(for: $0) } ?? []

        guard
            let image = StravaPostBuilder.renderSummaryCard(
                workout: workout,
                dominantZone: dominantZone,
                sortedSamples: samples,
                mmp: mmp,
                newPRFlags: prFlags,
                routeName: workout.savedRouteName ?? viewModel.routeName,
                totalElevationGain: workout.elevationGain > 0
                    ? workout.elevationGain : viewModel.totalElevationGain,
                zoneBuckets: buckets
            )
        else {
            summaryLogger.warning("Summary card render returned nil; Strava photo skipped.")
            return
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.88) else {
            summaryLogger.warning("Summary card JPEG encoding failed; Strava photo skipped.")
            return
        }

        switch await viewModel.uploadStravaSummaryCardPhoto(
            activityID: activityID,
            duplicateRecovery: duplicateRecovery,
            jpegData: jpegData
        ) {
        case .uploaded:
            break
        case .fallbackRequired:
            viewModel.presentStravaPhotoFallback(image)
        case .failed:
            summaryLogger.warning("Photo upload failed (non-fatal).")
        }
    }

    private func uploadToStrava(workout: Workout) {
        Task {
            if let completion = await viewModel.uploadToStrava(
                request: StravaUploadRequest(
                    workout: workout,
                    exportFormat: viewModel.selectedExportFormat,
                    hasRoute: viewModel.hasRoute,
                    routeService: viewModel.routeService,
                    routeName: workout.savedRouteName ?? viewModel.routeName,
                    totalElevationGain: workout.elevationGain > 0
                        ? workout.elevationGain : viewModel.totalElevationGain,
                    dominantPowerZone: PowerZone.zone(for: Int(workout.avgPower.rounded())),
                    zoneBuckets: zoneBuckets.map { (zone: $0.zone, percent: $0.percent) },
                    personalRecordNames: stravaPersonalRecordNames(for: workout),
                    descriptionOptions: stravaDescriptionOptions(),
                    preferredGearID: stravaPreferredGearID.isEmpty ? nil : stravaPreferredGearID
                )
            ) {
                await uploadStravaSummaryCardPhoto(
                    activityID: completion.activityID,
                    workout: workout,
                    duplicateRecovery: completion.duplicateRecovery
                )
            }
        }
    }

    // MARK: - Delete & Navigation

    private func promptDeleteWorkout() {
        viewModel.presentDeleteConfirmation()
    }

    private func saveWorkoutAsCustomTemplate() {
        guard let w = workout else { return }
        viewModel.saveWorkoutAsCustomTemplate(from: w)
    }

    private func repeatSavedCustomWorkout() {
        guard let action = viewModel.navigationActionForRepeatSavedCustomWorkout() else { return }
        applyNavigationAction(action)
    }

    private func deleteWorkout() {
        guard let workout else { return }
        guard let action = viewModel.deleteWorkout(workout) else { return }
        applyNavigationAction(action)
    }

    private func repeatStructuredWorkout() {
        guard let w = workout else { return }
        guard let action = viewModel.navigationActionForRepeatStructuredWorkout(w) else { return }
        applyNavigationAction(action)
    }

    private func popFromSummary() {
        applyNavigationAction(
            viewModel.navigationActionForClosingSummary(pathIsEmpty: navigationPath.isEmpty))
    }

    private func applyNavigationAction(_ action: WorkoutSummaryNavigationAction) {
        switch action {
        case .pop:
            navigationPath.removeLast()
        case .resetRoot:
            navigationPath = NavigationPath()
        case .route(let route):
            navigationPath = NavigationPath()
            navigationPath.append(route)
        }
    }
}

// MARK: - Summary Content View

// MARK: - Summary Content View

private struct SummaryContentView: View {
    let workout: Workout
    let linkedPlanDay: PlanDay?
    let sortedLaps: [LapSplit]
    let zoneBuckets: [ZoneBucket]
    let hrZoneBuckets: [HRZoneBucket]
    let dominantZone: PowerZone
    let heroAppeared: Bool

    @Binding var showExportModal: Bool
    @Binding var selectedExportFormat: ExportFormat
    let lastExportedFileURL: URL?
    let stravaAthleteDisplayName: String?
    let syncWorkoutsToAppleHealth: Bool
    let workoutSyncToHealthLastError: String?
    let onDone: () -> Void
    let onDelete: () -> Void
    let onOpenStravaUploader: () -> Void
    let onRepeatStructuredWorkout: () -> Void
    let customRepeatTemplateID: UUID?
    let onSaveAsCustomWorkout: () -> Void
    let onRepeatSavedCustomWorkout: () -> Void

    @Environment(\.isWideSummary) private var isWide

    // RPE Slider State
    @State private var rpeRating: Int = 5
    /// When on-device insight is unavailable, show the standalone power-zones card again.
    @State private var onDeviceInsightFailed = false

    private var hPad: CGFloat { isWide ? 40 : 20 }
    private var cardGap: CGFloat { isWide ? 16 : 12 }

    private var isOutdoor: Bool {
        return workout.savedRouteName != nil || workout.elevationGain > 0
    }

    /// Power zones appear inside the ride insight card while insight loads or succeeds; otherwise use the full zone card.
    private var showStandalonePowerZoneCard: Bool {
        workout.status != .completed || !workout.isValid || onDeviceInsightFailed
    }

    private func plannedVsActualCard(plan: PlanDay) -> some View {
        let ftp = PowerZone.ftp
        let plannedTSS = plan.estimatedPlannedTSS(ftp: ftp)
        let plannedMin = plan.durationMinutes
        let actualTSS = workout.tss
        let actualMin = max(1, Int(workout.duration / 60))

        return VStack(alignment: .leading, spacing: 10) {
            Text("PLANNED VS ACTUAL")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.1)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(plan.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                    Text(
                        plannedMin > 0
                            ? "\(plannedMin) min · est. TSS \(Int(plannedTSS))"
                            : "Est. TSS \(Int(plannedTSS))"
                    )
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("This ride")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("\(actualMin) min")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColor.mango)
                    Text("TSS \(Int(actualTSS))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func appleHealthSyncWarningBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.orange.opacity(0.95))
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Health sync")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !workout.isValid {
                        SummaryInvalidBanner()
                            .padding(.horizontal, hPad)
                            .padding(.top, 16)
                    }

                    if syncWorkoutsToAppleHealth,
                        let hkErr = workoutSyncToHealthLastError
                    {
                        appleHealthSyncWarningBanner(message: hkErr)
                            .padding(.horizontal, hPad)
                            .padding(.top, 12)
                    }

                    SummaryHeroHeader(
                        workout: workout,
                        linkedPlanDay: linkedPlanDay,
                        heroAppeared: heroAppeared,
                        onDone: onDone,
                        onDelete: onDelete
                    )
                    .padding(.horizontal, hPad)
                    .padding(.top, isWide ? 28 : 20)

                    if workout.status == .completed, workout.isValid {
                        SummaryOnDeviceInsightCard(
                            workout: workout,
                            zoneSegments: zoneBuckets.map {
                                RideInsightZoneSegment(
                                    zone: $0.zone, seconds: $0.seconds, percent: $0.percent)
                            },
                            powerZoneLine: zoneBuckets.map { z in
                                "Z\(z.zone.id) \(Int((z.percent * 100).rounded()))%"
                            }.joined(separator: ", "),
                            planLine: linkedPlanDay.map { plan in
                                let ftp = PowerZone.ftp
                                let tss = Int(plan.estimatedPlannedTSS(ftp: ftp))
                                return "\(plan.title) · est TSS \(tss)"
                            },
                            ftpWatts: PowerZone.ftp,
                            riderCallName: SummaryRiderNaming.stravaFirstName(
                                from: stravaAthleteDisplayName),
                            onDeviceInsightFailed: $onDeviceInsightFailed
                        )
                        .id(workout.id)
                        .padding(.horizontal, hPad)
                        .padding(.top, 12)
                    }

                    if let plan = linkedPlanDay {
                        plannedVsActualCard(plan: plan)
                            .padding(.horizontal, hPad)
                            .padding(.top, 12)
                    }

                    if workout.planDayID != nil {
                        Button(action: onRepeatStructuredWorkout) {
                            Label("Repeat this session", systemImage: "arrow.clockwise.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(AppColor.mango)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, hPad)
                        .padding(.top, 12)
                    }

                    if isWide {
                        wideBody
                    } else {
                        compactBody
                    }

                    if workout.planDayID == nil, workout.status == .completed, workout.isValid {
                        VStack(spacing: 10) {
                            Button(action: onSaveAsCustomWorkout) {
                                Label(
                                    "Save as custom workout",
                                    systemImage: "square.and.arrow.down.on.square"
                                )
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if customRepeatTemplateID != nil {
                                Button(action: onRepeatSavedCustomWorkout) {
                                    Label(
                                        "Repeat saved workout",
                                        systemImage: "arrow.clockwise.circle.fill"
                                    )
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppColor.mango)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, hPad)
                        .padding(.top, 12)
                    }

                    // RPE Rating Section
                    rpeSliderSection
                        .padding(.horizontal, hPad)
                        .padding(.vertical, 24)
                }
                .frame(maxWidth: isWide ? 1100 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: workout.id) { _, _ in
                onDeviceInsightFailed = false
            }
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
                    if showStandalonePowerZoneCard {
                        SummaryZoneCard(
                            title: "POWER ZONES", icon: "bolt.fill", buckets: zoneBuckets)
                    }
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
            .padding(.bottom, 20)
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
                if isOutdoor {
                    SummaryMetricCard(title: "ENVIRONMENT", icon: "leaf.fill") {
                        SummaryEnvironmentMetrics(workout: workout)
                    }
                } else {
                    SummaryMetricCard(title: "MOVEMENT", icon: "figure.indoor.cycle") {
                        SummaryMovementMetrics(workout: workout)
                    }
                }
            }
            .padding(.horizontal, hPad)
            .padding(.top, 20)

            if showStandalonePowerZoneCard {
                SummaryZoneCard(title: "POWER ZONES", icon: "bolt.fill", buckets: zoneBuckets)
                    .padding(.horizontal, hPad)
                    .padding(.top, 16)
            }

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
            if isOutdoor {
                SummaryMetricCard(title: "ENVIRONMENT", icon: "leaf.fill") {
                    SummaryEnvironmentMetrics(workout: workout)
                }
            } else {
                SummaryMetricCard(title: "MOVEMENT", icon: "figure.indoor.cycle") {
                    SummaryMovementMetrics(workout: workout)
                }
            }
            if workout.avgHR <= 0 {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: RPE Slider Section

    private var rpeSliderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SummarySectionHeader(title: "RATE OF PERCEIVED EXERTION", icon: "brain")

            HStack {
                Text("Easy")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.5))

                Slider(
                    value: Binding(
                        get: { Double(rpeRating) },
                        set: { rpeRating = Int($0) }
                    ),
                    in: 1...10,
                    step: 1
                )
                .tint(Color.accentColor)

                Text("Max")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("Score: \(rpeRating) / 10")
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(isWide ? 20 : 14)
        .cardStyle(cornerRadius: isWide ? 20 : 16)
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
    let linkedPlanDay: PlanDay?
    let heroAppeared: Bool
    let onDone: () -> Void
    let onDelete: () -> Void

    @Environment(\.isWideSummary) private var isWide

    private var oneSentenceInsight: String {
        if workout.duration > 3600 {
            return "Epic session! You burned \(Int(estimateCalories)) kcal."
        } else if workout.avgPower > 200 {
            return "Intense session! Way to push those watts."
        } else {
            return "Great job getting it done today!"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isWide ? 18 : 14) {
            HStack {
                planDayBadge
                savedOutdoorRouteBadge

                // Optional PR Badge
                if workout.avgPower > 250 {  // Adjust your condition for Personal Record
                    Text("🏆 PR")
                        .font(.system(size: isWide ? 13 : 11, weight: .bold))
                        .padding(.horizontal, isWide ? 12 : 8)
                        .padding(.vertical, isWide ? 6 : 4)
                        .background(AppColor.yellow.opacity(0.1))
                        .foregroundStyle(AppColor.yellow)
                        .clipShape(Capsule())
                }
            }

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

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

            // Humanized insight
            Text(oneSentenceInsight)
                .font(.system(size: isWide ? 16 : 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
                .opacity(heroAppeared ? 1 : 0)
                .offset(y: heroAppeared ? 0 : 8)
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
        if let day = linkedPlanDay {
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

    private var heroStatsRow: some View {
        HStack(spacing: 0) {
            heroStat(
                value: String(format: "%.1f", workout.distance / 1000), unit: "km",
                icon: "road.lanes")
            Spacer()
            heroStat(
                value: String(format: "%.0f", estimateCalories), unit: "kcal", icon: "flame.fill")
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.system(size: isWide ? 11 : 9))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    private var estimateCalories: Double {
        Double(
            WorkoutExportService.estimateCalories(
                avgPower: workout.avgPower, durationSeconds: workout.duration))
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

// MARK: - Metric Card Container (Glassmorphic)

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
                    .font(.system(size: size * 0.5, design: .monospaced))
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
                MetricValueView(
                    value: "\(Int(workout.avgPower))", unit: "W", color: avgZone.color,
                    size: primarySize)
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
                MetricCellView(
                    label: "MAX", value: "\(workout.maxPower)", unit: "W", color: maxZone.color)
                Spacer()
                MetricCellView(
                    label: "NP", value: "\(Int(workout.normalizedPower))", unit: "W",
                    color: AppColor.yellow)
                Spacer()
                MetricCellView(
                    label: "ZONE", value: "Z\(avgZone.id)", unit: "", color: avgZone.color)
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
                MetricValueView(
                    value: String(format: "%.0f", workout.tss), unit: "TSS", color: tColor,
                    size: primarySize)
                Spacer()
            }

            HStack(spacing: 0) {
                MetricCellView(
                    label: "IF", value: String(format: "%.2f", workout.intensityFactor), unit: "",
                    color: ifColor)
                Spacer()
                MetricCellView(
                    label: "KCAL", value: String(format: "%.0f", estimateCalories), unit: "",
                    color: AppColor.orange)
                Spacer()
                MetricCellView(
                    label: "VI", value: String(format: "%.2f", vi), unit: "",
                    color: .white.opacity(0.7))
            }
        }
    }

    private var estimateCalories: Double {
        Double(
            WorkoutExportService.estimateCalories(
                avgPower: workout.avgPower, durationSeconds: workout.duration))
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
                MetricValueView(
                    value: "\(Int(workout.avgHR))", unit: "bpm", color: AppColor.heartRate,
                    size: primarySize)
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
                MetricCellView(
                    label: "MAX HR", value: "\(workout.maxHR)", unit: "bpm", color: AppColor.red)
                Spacer()
                MetricCellView(
                    label: "HR ZONE", value: "Z\(hrZone.id)", unit: "", color: hrZone.color)
                Spacer()
                MetricCellView(
                    label: "RANGE", value: "\(workout.maxHR - Int(workout.avgHR))", unit: "Δ",
                    color: .white.opacity(0.5))
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
                                .font(
                                    .system(
                                        size: isWide ? 16 : 13, weight: .bold, design: .monospaced)
                                )
                                .foregroundStyle(AppColor.success)
                        }
                        Text("elevation")
                            .font(.system(size: isWide ? 9 : 8))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }

            HStack(spacing: 0) {
                MetricCellView(
                    label: "CADENCE", value: "\(Int(workout.avgCadence))", unit: "rpm",
                    color: AppColor.blue)
                Spacer()
                MetricCellView(
                    label: "SPEED", value: String(format: "%.1f", workout.displayAverageSpeedKmh),
                    unit: "km/h", color: .white.opacity(0.7))
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
                lapText(
                    AppFormat.duration(lap.duration), width: colDur, alignment: .leading,
                    isHeader: false)
                Text("\(Int(lap.avgPower))W")
                    .font(.system(size: isWide ? 13 : 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lapZone.color)
                    .frame(width: colAvg, alignment: .trailing)
                lapText("\(lap.maxPower)W", width: colMax, alignment: .trailing, isHeader: false)
                if hasHR {
                    lapText(
                        lap.avgHR > 0 ? "\(Int(lap.avgHR))" : "—", width: colHR,
                        alignment: .trailing, isHeader: false)
                }
                lapText(
                    String(format: "%.2fkm", lap.distance / 1000), width: colDist,
                    alignment: .trailing, isHeader: false)
                if isWide {
                    lapText(
                        lap.avgCadence > 0 ? "\(Int(lap.avgCadence))" : "—", width: colCad,
                        alignment: .trailing, isHeader: false)
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

    private func lapText(_ text: String, width: CGFloat, alignment: Alignment, isHeader: Bool)
        -> some View
    {
        Text(text)
            .font(
                .system(
                    size: isHeader ? (isWide ? 10 : 9) : (isWide ? 13 : 11),
                    weight: isHeader ? .bold : .regular, design: .monospaced)
            )
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
    let hasRoute: Bool
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

            if selectedExportFormat == .gpx, hasRoute,
                RidePreferences.shared.gpxPrivacyTrimStartMeters > 0
                    || RidePreferences.shared.gpxPrivacyTrimEndMeters > 0
            {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.lefthalf.filled")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.success.opacity(0.85))
                    Text(
                        "Privacy trim is on in Settings → Data, privacy & alerts. The GPX shortens the start and end of the track."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

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
        let canExport = WorkoutExportService.canExport(
            format: format, hasRoute: hasRoute)
        let isSelected = selectedExportFormat == format
        let titleColor: Color =
            isSelected ? .white : (canExport ? .white.opacity(0.5) : .white.opacity(0.2))
        let subtitleColor: Color = isSelected ? .white.opacity(0.5) : .white.opacity(0.2)
        let bgColor: Color = isSelected ? AppColor.orange.opacity(0.12) : Color.white.opacity(0.02)
        let borderColor: Color =
            isSelected ? AppColor.orange.opacity(0.3) : Color.white.opacity(0.05)
        let subtitleText: String =
            format == .tcx ? "Indoor" : (hasRoute ? "Route loaded" : "Needs route")

        return Button {
            selectedExportFormat = format
        } label: {
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
        let canExportSelected = WorkoutExportService.canExport(
            format: selectedExportFormat, hasRoute: hasRoute)
        let fgColor: Color = canExportSelected ? .white : .white.opacity(0.3)
        let bgOpacity: Double = canExportSelected ? 0.12 : 0.04
        let borderOpacity: Double = canExportSelected ? 0.3 : 0.1

        return Button {
            onExport(selectedExportFormat)
        } label: {
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
    @Environment(WorkoutViewModel.self) private var viewModel
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.isStravaConnected {
                notConnectedView
            } else {
                connectedForm
            }
        }
        .task(id: viewModel.isStravaConnected) {
            await viewModel.refreshStravaBikesIfNeeded()
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
                            Text(
                                stravaDescriptionInput.isEmpty
                                    ? "No description" : stravaDescriptionInput
                            )
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

                if viewModel.stravaBikesLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text("Loading bikes…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                } else if viewModel.stravaBikesLoadFailed {
                    Text(
                        "Could not load bikes. Disconnect and connect Strava again to grant profile access."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                } else if viewModel.stravaBikes.isEmpty {
                    Text(
                        "No bikes on your Strava profile. Add a bike on strava.com to link activities."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                } else {
                    Picker("Bike", selection: $preferredGearID) {
                        Text("None").tag("")
                        ForEach(viewModel.stravaBikes) { bike in
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
            Text(viewModel.stravaAthleteDisplayName ?? "Connected")
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
                        .foregroundStyle(
                            uploadPhotoAfterUpload
                                ? AppColor.mango.opacity(0.7) : .white.opacity(0.3))
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

    private func fieldBlock<Content: View>(label: String, @ViewBuilder content: () -> Content)
        -> some View
    {
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
                if viewModel.isStravaBusy {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                }
                Text(viewModel.isStravaBusy ? "Uploading…" : "Upload to Strava")
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
        .disabled(viewModel.isStravaBusy)
        .opacity(viewModel.isStravaBusy ? 0.7 : 1)
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

        if let err = viewModel.stravaLastError, !err.isEmpty {
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

// MARK: - Preview

@MainActor
private final class _SummaryPreviewPersistenceRepository: WorkoutPersistenceRepositoryProtocol {
    func saveWorkoutAsCustomTemplate(from workout: Workout) throws -> UUID? { nil }
    func saveCustomWorkoutTemplate(name: String, intervals: [IntervalSegment]) throws -> UUID { UUID() }
    func deleteWorkout(_ workout: Workout) throws {}
    func saveOutdoorRide(workout: Workout, splits: [LapSplit]) throws {}
    func saveImportedWorkout(_ payload: ImportedWorkoutPayload) throws -> Workout {
        Workout(startDate: payload.startDate)
    }
    func fetchCustomWorkoutTemplate(id: UUID) throws -> PlanDay? { nil }
    func fetchSortedSamples(forWorkoutID id: PersistentIdentifier) async -> [WorkoutSampleData] { [] }
}

#Preview {
    SummaryView(
        workoutID: UUID(),
        navigationPath: .constant(NavigationPath()),
        viewModel: WorkoutViewModel(
            stravaService: StravaService(),
            routeService: RouteManager(),
            personalRecordsService: PersonalRecords.shared,
            healthKitService: HealthKitManager(),
            trainingPlanLookupService: TrainingPlanLookupService(),
            workoutPersistenceRepository: _SummaryPreviewPersistenceRepository()
        )
    )
    .modelContainer(
        for: [
            Workout.self, WorkoutSample.self, LapSplit.self, TrainingPlanProgress.self,
            WorkoutRAGChunk.self,
        ],
        inMemory: true)
}

private struct SummaryEnvironmentMetrics: View {
    let workout: Workout
    @Environment(\.isWideSummary) private var isWide

    var body: some View {
        HStack {
            MetricCellView(
                label: "ELEVATION",
                value: String(format: "%.0f", workout.elevationGain),
                unit: "m",
                color: .orange
            )
            Spacer()
        }
    }
}

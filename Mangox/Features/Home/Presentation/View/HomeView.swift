import CoreBluetooth
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - Weekly TSS (home dashboard)

private struct WeekDayTSS: Identifiable {
    let id: String
    /// Narrow weekday label for the column’s calendar date (matches locale week order).
    let day: String
    let tss: Double
    let color: Color

    init(id: String, day: String, tss: Double, color: Color) {
        self.id = id
        self.day = day
        self.tss = tss
        self.color = color
    }
}

// MARK: - HomeView

private struct HomeTrainingCache {
    let weeklyTSS: Double
    let chronicLoad: Double
    let acwr: Double
    let weekRides: Int
    let weekBars: [WeekDayTSS]
}

struct HomeView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(DataSourceCoordinator.self) private var dataSource
    @Environment(LocationManager.self) private var locationManager
    @Environment(WhoopService.self) private var whoopService
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int

    @Environment(AIService.self) private var aiService

    @State private var trainingCache: HomeTrainingCache?
    @State private var trainingCacheRecomputeTask: Task<Void, Never>?
    @State private var trainingCacheGeneration: UInt64 = 0
    /// After an empty-workout snapshot, the next non-empty fetch should not wait on debounce.
    @State private var trainingCacheHasSeenWorkouts = false
    /// On-device 1–2 word readiness label for the training status header badge. Nil while generating or unavailable.
    @State private var homeTrainingStatusLabel: String?

    private static let recentWorkoutsDescriptor: FetchDescriptor<Workout> = {
        var d = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 150
        return d
    }()

    @Query(HomeView.recentWorkoutsDescriptor) private var workouts: [Workout]

    private static let planProgressDescriptor: FetchDescriptor<TrainingPlanProgress> = {
        var d = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 256
        return d
    }()

    @Query(HomeView.planProgressDescriptor) private var allProgress: [TrainingPlanProgress]

    // MARK: - Design System

    private var bg: Color { AppColor.bg }
    private var mango: Color { AppColor.mango }
    private var success: Color { AppColor.success }
    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textSecondary: Color { .white.opacity(AppOpacity.textSecondary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColor.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                minimalTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 16) {
                        FTPRefreshScope {
                            VStack(spacing: 16) {
                                trainingStatusCard
                                nextWorkoutFromPlanCard
                                if needsFTPTest {
                                    ftpPromptCard
                                }
                            }
                        }
                        recentRidesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            locationManager.setup()
            // Pre-warm BLE: start reconnecting to known devices as soon as the
            // home screen appears, so the trainer is already connected (or
            // connecting) by the time the user taps "Ride".
            if bleManager.bluetoothState == .poweredOn,
                !bleManager.trainerConnectionState.isConnected,
                !dataSource.wifiConnectionState.isConnected
            {
                bleManager.reconnectOrScan()
            }
        }
        .onChange(of: workouts, initial: true) { _, _ in
            scheduleTrainingCacheRecompute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxWorkoutAggregatesMayHaveChanged)) {
            _ in
            scheduleTrainingCacheRecompute()
        }
        .task {
            await whoopService.refreshLinkedDataIfStale()
        }
        .task(id: trainingCacheGeneration) {
            guard trainingCache != nil, OnDeviceCoachEngine.isSystemModelAvailable else { return }
            let factSheet = aiService.coachFactSheetText(modelContext: modelContext)
            homeTrainingStatusLabel = try? await OnDeviceCoachEngine.generateHomeTrainingInsight(
                factSheet: factSheet)
        }
    }

    /// Coalesces SwiftData churn; first populated snapshot runs immediately, then debounces.
    private func scheduleTrainingCacheRecompute() {
        if workouts.isEmpty {
            trainingCacheRecomputeTask?.cancel()
            trainingCacheGeneration += 1
            trainingCacheHasSeenWorkouts = false
            let dto = HomeTrainingAggregateMath.compute(
                slices: [],
                now: Date(),
                timeZone: .current,
                locale: .current
            )
            trainingCache = trainingCacheFromDTO(dto)
            return
        }
        if !trainingCacheHasSeenWorkouts {
            trainingCacheHasSeenWorkouts = true
            trainingCacheRecomputeTask?.cancel()
            Task { @MainActor in
                await runTrainingCacheGeneration()
            }
            return
        }
        if trainingCache == nil {
            trainingCacheRecomputeTask?.cancel()
            Task { @MainActor in
                await runTrainingCacheGeneration()
            }
        } else {
            trainingCacheRecomputeTask?.cancel()
            trainingCacheRecomputeTask = Task { @MainActor in
                // 120ms debounce balances responsiveness with CPU efficiency
                // Aggressive churn protection: coalesces rapid SwiftData notifications
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await runTrainingCacheGeneration()
            }
        }
    }

    @MainActor
    private func runTrainingCacheGeneration() async {
        await MangoxDebugPerformance.runInterval("Home.trainingCache") {
            await runTrainingCacheGenerationBody()
        }
    }

    @MainActor
    private func runTrainingCacheGenerationBody() async {
        trainingCacheGeneration += 1
        let generation = trainingCacheGeneration
        let slices = workouts.map { HomeWorkoutMetricSlice(startDate: $0.startDate, tss: $0.tss) }
        let now = Date()
        let timeZone = TimeZone.current
        let locale = Locale.current
        let dto = await Task.detached(priority: .utility) {
            await HomeTrainingAggregateMath.compute(
                slices: slices,
                now: now,
                timeZone: timeZone,
                locale: locale
            )
        }.value
        guard generation == trainingCacheGeneration else { return }
        trainingCache = trainingCacheFromDTO(dto)
    }

    private func trainingCacheFromDTO(_ dto: HomeTrainingCacheDTO) -> HomeTrainingCache {
        let weekBars = dto.weekBars.map { bar in
            WeekDayTSS(
                id: bar.id,
                day: bar.day,
                tss: bar.tss,
                color: weekBarColor(tss: bar.tss)
            )
        }
        return HomeTrainingCache(
            weeklyTSS: dto.weeklyTSS,
            chronicLoad: dto.chronicLoad,
            acwr: dto.acwr,
            weekRides: dto.weekRides,
            weekBars: weekBars
        )
    }

    private func weekBarColor(tss: Double) -> Color {
        if tss == 0 {
            return .clear
        } else if tss < 50 {
            return success.opacity(0.6)
        } else if tss < 100 {
            return AppColor.yellow
        } else if tss < 150 {
            return mango
        } else {
            return AppColor.orange
        }
    }

    // MARK: - Top Bar

    private var minimalTopBar: some View {
        HStack(spacing: 8) {
            Text("Mangox")
                .font(.title2.weight(.bold))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)
        }
    }

    // MARK: - Training Status Card

    private var trainingStatusCard: some View {
        let weeklyTSS = trainingCache?.weeklyTSS ?? 0
        let chronicLoad = trainingCache?.chronicLoad ?? 300
        let acwr = trainingCache?.acwr ?? 0
        let form = formData(acwr: acwr)
        let acwrText = chronicLoad > 0 && !workouts.isEmpty ? String(format: "%.1f", acwr) : "--"

        return VStack(alignment: .leading, spacing: 14) {
            // Header with form badge
            HStack(spacing: 10) {
                Text("TRAINING STATUS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(textTertiary)
                    .tracking(1.0)

                Spacer()

                // ACWR tint + on-device status words (falls back to ACWR band label)
                HStack(spacing: 5) {
                    Image(systemName: form.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(form.color)
                    Text(trainingStatusBadgeText(form: form))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(form.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(form.color.opacity(0.12))
                .clipShape(Capsule())
            }

            // 4-metric row
            HStack(spacing: 0) {
                trainingMetric(
                    value: "\(Int(weeklyTSS))",
                    label: "WEEK TSS",
                    color: mango
                )
                metricDivider
                trainingMetric(
                    value: "\(trainingCache?.weekRides ?? 0)",
                    label: "RIDES",
                    color: AppColor.blue
                )
                metricDivider
                trainingMetric(
                    value: "\(PowerZone.ftp)",
                    label: "FTP",
                    color: AppColor.orange
                )
                metricDivider
                trainingMetric(
                    value: acwrText,
                    label: "ACWR",
                    color: form.color
                )
            }

            // Weekly micro-bars
            let weekBars = trainingCache?.weekBars ?? []
            let maxTSS = weekBars.map(\.tss).max() ?? 1
            HStack(spacing: 4) {
                ForEach(weekBars) { dayData in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(dayData.tss == 0 ? Color.white.opacity(0.06) : dayData.color)
                            .frame(
                                height: maxTSS > 0 && dayData.tss > 0
                                    ? max(3, CGFloat(dayData.tss / maxTSS) * 24)
                                    : 3)
                        Text(String(dayData.day.prefix(1)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40, alignment: .bottom)

            if whoopService.isConnected, whoopService.isConfigured {
                whoopTrainingStrip
            }
        }
        .padding(16)
        .cardStyle(cornerRadius: 14)
    }

    private var whoopTrainingStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.whoop)
                Text("WHOOP")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(textTertiary)
                    .tracking(0.6)

                if let pct = whoopService.latestRecoveryScore {
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(whoopService.readinessAccentColor)
                    Text("recovery")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(textTertiary)
                } else {
                    Text("—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(textTertiary)
                }

                if let rhr = whoopService.latestRecoveryRestingHR {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(textTertiary.opacity(0.35))
                    Text("RHR \(rhr)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(textTertiary)
                }
                if let hrv = whoopService.latestRecoveryHRV {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(textTertiary.opacity(0.35))
                    Text("HRV \(hrv)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(textTertiary)
                }

                Spacer(minLength: 4)

                if let last = whoopService.lastSuccessfulRefreshAt {
                    Text(last.formatted(.relative(presentation: .named)))
                        .font(.system(size: 9))
                        .foregroundStyle(textTertiary.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var nextWorkoutFromPlanCard: some View {
        Group {
            if let nw = PlanLibrary.nextScheduledWorkout(
                allProgress: allProgress, modelContext: modelContext)
            {
                Button {
                    navigationPath.append(
                        AppRoute.connectionForPlan(planID: nw.planID, dayID: nw.day.id))
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(mango.opacity(0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: "calendar.badge.clock")
                                .font(.title3)
                                .foregroundStyle(mango)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEXT WORKOUT")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(textTertiary)
                                .tracking(0.8)
                            Text(nw.day.title)
                                .font(.headline)
                                .foregroundStyle(textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(nw.plan.name)
                                .font(.caption)
                                .foregroundStyle(textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(textTertiary)
                    }
                    .padding(18)
                    .cardStyle(cornerRadius: 14)
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Next workout: \(nw.day.title)")
            }
        }
    }

    private func trainingMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(textTertiary)
                .tracking(1.0)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(AppOpacity.divider))
            .frame(width: 1, height: 28)
    }

    private func formData(acwr: Double) -> (color: Color, icon: String, description: String) {
        if acwr < 0.8 {
            return (success, "leaf.fill", "Fresh")
        } else if acwr < 1.0 {
            return (AppColor.yellow, "bolt.fill", "Building")
        } else if acwr <= 1.3 {
            return (mango, "flame.fill", "Optimal")
        } else if acwr <= 1.5 {
            return (AppColor.orange, "exclamationmark.triangle.fill", "High load")
        } else {
            return (AppColor.red, "xmark.circle.fill", "Overreaching")
        }
    }

    private func trainingStatusBadgeText(form: (color: Color, icon: String, description: String)) -> String {
        if let s = homeTrainingStatusLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return form.description
    }

    // MARK: - FTP Prompt

    private var needsFTPTest: Bool {
        if !PowerZone.hasSetFTP { return true }
        if let lastUpdate = PowerZone.lastFTPUpdate,
            Date().timeIntervalSince(lastUpdate) > 42 * 24 * 3600
        {
            return true
        }
        return false
    }

    private var ftpPromptCard: some View {
        Button {
            navigationPath.append(AppRoute.ftpSetup)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppColor.orange.opacity(0.15))
                        .frame(width: 46, height: 46)

                    Image(systemName: "bolt.heart.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(PowerZone.hasSetFTP ? "Recalibrate FTP" : "Set Your FTP")
                        .font(.headline)
                        .foregroundStyle(textPrimary)

                    Text(
                        PowerZone.hasSetFTP
                            ? "It's been over 6 weeks since your last baseline."
                            : "Required for accurate power zones"
                    )
                    .font(.subheadline)
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text("20 min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(AppColor.orange.opacity(0.15))
                    )
            }
            .padding(18)
            .cardStyle(cornerRadius: 14)
        }
        .buttonStyle(MangoxPressStyle())
    }

    // MARK: - Recent Rides

    private var recentRidesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("RECENT RIDES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(textTertiary)
                    .tracking(1.0)

                Spacer()

                Button {
                    selectedTab = 1
                } label: {
                    Text("See all")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(mango)
                }
            }
            .padding(.horizontal, 4)

            if workouts.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "bicycle")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
                    Text("No rides yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(textTertiary)
                    Text(
                        "Tap Indoor or Outdoor above to ride. Use the Coach tab for your training plan."
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HomeRecentRidesTableHeader()

                    VStack(spacing: 8) {
                        ForEach(Array(workouts.prefix(5))) { workout in
                            Button {
                                navigationPath.append(AppRoute.summary(workoutID: workout.id))
                            } label: {
                                HomeRecentRideRow(workout: workout)
                            }
                            .buttonStyle(MangoxPressStyle())
                        }
                    }
                }
            }
        }
    }

}

// MARK: - Workout Extension

extension Workout {
    var hasPowerData: Bool {
        avgPower > 0 || normalizedPower > 0
    }

    var zoneDistribution: [Double] {
        guard hasPowerData else { return [] }
        return [0.1, 0.25, 0.35, 0.2, 0.1]
    }
}

// MARK: - Date Extension

extension Date {
    func relativeFormatted() -> String {
        Date.relativeFormatter.localizedString(for: self, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Preview

#Preview {
    HomeView(navigationPath: .constant(NavigationPath()), selectedTab: .constant(0))
        .modelContainer(for: [Workout.self, WorkoutRAGChunk.self, TrainingPlanProgress.self])
        .environment(HealthKitManager())
        .environment(WhoopService())
}

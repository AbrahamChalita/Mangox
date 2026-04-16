import CoreBluetooth
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int

    @Environment(StravaService.self) private var stravaService
    @State private var viewModel: HomeViewModel

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

    init(
        navigationPath: Binding<NavigationPath>,
        selectedTab: Binding<Int>,
        viewModel: HomeViewModel
    ) {
        self._navigationPath = navigationPath
        self._selectedTab = selectedTab
        self._viewModel = State(initialValue: viewModel)
    }

    // MARK: - Design System

    private var bg: Color { AppColor.bg }
    private var mango: Color { AppColor.mango }
    private var success: Color { AppColor.success }
    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textSecondary: Color { .white.opacity(AppOpacity.textSecondary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    // MARK: - Whoop readiness accent color (Presentation-layer concern)

    private var whoopReadinessAccentColor: Color {
        guard let score = viewModel.whoopRecoveryScore else { return AppColor.whoop.opacity(0.85) }
        if score >= 67 { return AppColor.success }
        if score >= 34 { return AppColor.yellow }
        return AppColor.orange
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AppColor.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                minimalTopBar
                    .padding(.horizontal, MangoxSpacing.page)
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
                    .padding(.horizontal, MangoxSpacing.lg.rawValue)
                    .padding(.top, 8)
                    .padding(.bottom, MangoxSpacing.page)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            viewModel.prewarmLocationServices()
        }
        .onChange(of: workouts, initial: true) { _, _ in
            viewModel.scheduleTrainingRefresh(workouts: workouts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxWorkoutAggregatesMayHaveChanged)) {
            _ in
            viewModel.scheduleTrainingRefresh(workouts: workouts)
        }
        .task {
            await viewModel.refreshWhoopIfStale()
        }
        .task(id: viewModel.trainingStatusRequestID) {
            await viewModel.generateAITrainingInsight()
        }
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

    private var homeHeaderTitle: String {
        RiderIdentityDisplay.resolvedTitle(stravaDisplayName: stravaService.athleteDisplayName)
    }

    private var minimalTopBar: some View {
        HStack(spacing: 8) {
            Text(homeHeaderTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)
        }
    }

    // MARK: - Training Status Card

    private var trainingStatusCard: some View {
        let weeklyTSS = viewModel.weeklyTSS
        let chronicLoad = viewModel.chronicLoad > 0 ? viewModel.chronicLoad : 300
        let acwr = viewModel.acwr
        let form = formData(acwr: acwr)
        let acwrText = chronicLoad > 0 && !workouts.isEmpty ? String(format: "%.1f", acwr) : "--"

        return VStack(alignment: .leading, spacing: 14) {
            // Header with form badge
            HStack(spacing: 10) {
                MangoxSectionLabel(title: "Training Status", horizontalPadding: 0)

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
                    value: "\(viewModel.weekRides)",
                    label: "RIDES",
                    color: AppColor.blue
                )
                metricDivider
                trainingMetric(
                    value: "\(viewModel.ftp)",
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
            let weekBars = viewModel.weekBars
            let maxTSS = weekBars.map(\.tss).max() ?? 1
            HStack(spacing: 4) {
                ForEach(weekBars) { dayData in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(dayData.tss == 0 ? Color.white.opacity(0.06) : weekBarColor(tss: dayData.tss))
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

            if viewModel.whoopConnected, viewModel.whoopConfigured {
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

                if let pct = viewModel.whoopRecoveryScore {
                    Text(String(format: "%.0f%%", pct))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(whoopReadinessAccentColor)
                    Text("recovery")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(textTertiary)
                } else {
                    Text("—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(textTertiary)
                }

                if let rhr = viewModel.whoopRestingHR {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(textTertiary.opacity(0.35))
                    Text("RHR \(rhr)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(textTertiary)
                }
                if let hrv = viewModel.whoopHRV {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(textTertiary.opacity(0.35))
                    Text("HRV \(hrv)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(textTertiary)
                }

                Spacer(minLength: 4)

                if let last = viewModel.whoopLastRefreshAt {
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
            if let nw = viewModel.nextScheduledWorkout(allProgress: allProgress) {
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
        if let s = viewModel.homeTrainingStatusLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return form.description
    }

    // MARK: - FTP Prompt

    private var needsFTPTest: Bool {
        if !viewModel.hasSetFTP { return true }
        if let lastUpdate = viewModel.lastFTPUpdate,
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
                    Text(viewModel.hasSetFTP ? "Recalibrate FTP" : "Set Your FTP")
                        .font(.headline)
                        .foregroundStyle(textPrimary)

                    Text(
                        viewModel.hasSetFTP
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
                MangoxSectionLabel(title: "Recent Rides", horizontalPadding: 0)

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
                                HomeRecentRideRow(
                                    workout: workout,
                                    trainingPlanLookupService: viewModel.trainingPlanLookupService
                                )
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
    HomeView(
        navigationPath: .constant(NavigationPath()),
        selectedTab: .constant(0),
        viewModel: HomeViewModel(
            bleService: BLEManager(),
            dataSourceService: DataSourceCoordinator(bleManager: BLEManager(), wifiService: WiFiTrainerService()),
            locationService: LocationManager(),
            whoopService: WhoopService(),
            aiService: AIService(),
            trainingPlanLookupService: TrainingPlanLookupService()
        )
    )
        .modelContainer(for: [Workout.self, WorkoutRAGChunk.self, TrainingPlanProgress.self])
        .environment(HealthKitManager())
        .environment(WhoopService())
        .environment(StravaService())
}

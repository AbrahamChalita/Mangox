import CoreBluetooth
import CoreLocation
import SwiftData
import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int

    @Environment(\.launchOverlayVisible) private var launchOverlayVisible
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
        .task(id: "\(viewModel.trainingStatusRequestID)-\(launchOverlayVisible)") {
            guard !launchOverlayVisible else { return }
            // Defer the on-device coach badge until the home shell is already visible.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
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

    private var homeGreetingName: String {
        let token = homeHeaderTitle
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .punctuationCharacters)
        return token?.isEmpty == false ? token! : homeHeaderTitle
    }

    private var homeGreetingLine: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 5..<12:
            salutation = "Morning"
        case 12..<17:
            salutation = "Afternoon"
        default:
            salutation = "Evening"
        }
        return "\(salutation), \(homeGreetingName)"
    }

    private var minimalTopBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(homeGreetingLine)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.mango)

                Text("Mangox")
                    .font(MangoxFont.title.value)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Date(), format: .dateTime.month(.abbreviated).day())
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg2)
                Text(Date(), format: .dateTime.weekday(.wide))
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Training Status Card

    private var trainingStatusCard: some View {
        let weeklyTSS = viewModel.weeklyTSS
        let chronicLoad = viewModel.chronicLoad > 0 ? viewModel.chronicLoad : 0
        let acwr = viewModel.acwr
        let form = formData(acwr: acwr)
        let acwrText = chronicLoad > 0 && !workouts.isEmpty ? String(format: "%.1f", acwr) : "—"
        let weekBars = viewModel.weekBars
        let maxTSS = max(weekBars.map(\.tss).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAINING SNAPSHOT")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.mango)
                        .tracking(1.4)

                    Text(trainingStatusBadgeText(form: form))
                        .font(MangoxFont.bodyBold.value)
                        .foregroundStyle(textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                MangoxStatusPill(
                    text: form.description,
                    color: form.color,
                    icon: form.icon
                )
            }
            .padding(16)

            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            HStack(spacing: 0) {
                snapshotMetricCell(
                    label: "CTL · FIT",
                    value: chronicLoad > 0 ? "\(Int(chronicLoad.rounded()))" : "—",
                    detail: chronicLoad > 0 ? "\(viewModel.weekRides) rides" : "No load yet",
                    color: AppColor.blue
                )
                metricDivider
                snapshotMetricCell(
                    label: "WEEK · TSS",
                    value: "\(Int(weeklyTSS.rounded()))",
                    detail: "FTP \(viewModel.ftp)W",
                    color: AppColor.mango
                )
                metricDivider
                snapshotMetricCell(
                    label: "ACWR · LOAD",
                    value: acwrText,
                    detail: form.description.uppercased(),
                    color: form.color
                )
            }

            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("LOAD · 7D")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1.2)
                    Spacer()
                    Text("\(viewModel.weekRides) SESSIONS")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg2)
                }

                HStack(spacing: 4) {
                    ForEach(weekBars) { dayData in
                        VStack(spacing: 6) {
                            Rectangle()
                                .fill(dayData.tss == 0 ? AppColor.bg4 : weekBarColor(tss: dayData.tss))
                                .frame(
                                    height: dayData.tss > 0
                                        ? max(4, CGFloat(dayData.tss / maxTSS) * 28)
                                        : 4
                                )

                            Text(String(dayData.day.prefix(1)))
                                .mangoxFont(.micro)
                                .foregroundStyle(AppColor.fg3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 42, alignment: .bottom)

                if viewModel.whoopConnected, viewModel.whoopConfigured {
                    whoopTrainingStrip
                }
            }
            .padding(16)
        }
        .background(AppColor.bg2)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
    }

    private func snapshotMetricCell(label: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .mangoxFont(.label)
                .foregroundStyle(color.opacity(0.92))
                .tracking(1.2)

            Text(value)
                .font(MangoxFont.value.value)
                .foregroundStyle(textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Text(detail)
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.fg3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var whoopTrainingStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .background(AppColor.hair)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.whoop)
                Text("WHOOP")
                    .mangoxFont(.label)
                    .foregroundStyle(textTertiary)
                    .tracking(1.0)

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
                        .mangoxFont(.micro)
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
                let plannedTSS = Int(nw.day.estimatedPlannedTSS(ftp: PowerZone.ftp).rounded())
                Button {
                    navigationPath.append(
                        AppRoute.connectionForPlan(planID: nw.planID, dayID: nw.day.id))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("TODAY · \(nw.plan.name.uppercased())")
                                .mangoxFont(.label)
                                .foregroundStyle(AppColor.mango)
                                .tracking(1.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .layoutPriority(1)

                            Spacer(minLength: 6)

                            Text(plannedMetaLine(day: nw.day, plannedTSS: plannedTSS))
                                .mangoxFont(.caption)
                                .foregroundStyle(AppColor.fg2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }

                        HStack(spacing: 8) {
                            Text(nw.day.title)
                                .mangoxFont(.bodyBold)
                                .foregroundStyle(textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 6)

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.fg2)
                        }

                        workoutProfile(for: nw.day, rowHeight: 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppColor.bg2)
                    .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1))
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Next workout: \(nw.day.title)")
            }
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColor.hair)
            .frame(width: 1)
    }

    private func plannedMetaLine(day: PlanDay, plannedTSS: Int) -> String {
        var parts: [String] = []
        if day.durationMinutes > 0 { parts.append("\(day.durationMinutes) MIN") }
        if plannedTSS > 0 { parts.append("\(plannedTSS) TSS") }
        if day.dayType != .rest { parts.append(day.zone.label.uppercased()) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func workoutProfile(for day: PlanDay, compact: Bool = false, rowHeight overrideHeight: CGFloat? = nil) -> some View {
        let rowHeight: CGFloat = overrideHeight ?? (compact ? 26 : 34)
        let barScale = rowHeight / 34
        HStack(alignment: .bottom, spacing: compact ? 2 : 3) {
            if day.hasStructuredIntervals {
                ForEach(Array(day.intervals.prefix(7).enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.zone.color)
                        .frame(maxWidth: .infinity)
                        .frame(height: profileBarHeight(for: segment.zone) * barScale)
                }
            } else {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(day.zone.color.opacity(day.dayType == .rest ? 0.35 : 0.9))
                        .frame(maxWidth: .infinity)
                        .frame(height: profileBarHeight(for: day.zone) * barScale)
                }
            }
        }
        .frame(height: rowHeight, alignment: .bottom)
    }

    private func profileBarHeight(for zone: TrainingZoneTarget) -> CGFloat {
        switch zone {
        case .rest, .none:
            return 10
        case .z1, .z1z2:
            return 14
        case .z2, .z2z3:
            return 20
        case .z3, .z3z4, .mixed:
            return 28
        case .z4, .z4z5, .all:
            return 34
        case .z5, .z3z5:
            return 38
        }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("FTP BASELINE")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.orange)
                        .tracking(1.4)

                    Text(viewModel.hasSetFTP ? "Recalibrate FTP" : "Set Your FTP")
                        .font(MangoxFont.value.value)
                        .foregroundStyle(textPrimary)

                    Text(
                        viewModel.hasSetFTP
                            ? "It's been over 6 weeks since your last baseline."
                            : "Required for accurate power zones"
                    )
                    .mangoxFont(.body)
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Text("20 MIN")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.orange)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.fg2)
                }
            }
            .padding(16)
            .background(AppColor.bg2)
            .overlay(Rectangle().stroke(AppColor.orange.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(MangoxPressStyle())
    }

    // MARK: - Recent Rides

    private var recentRidesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ACTIVITY")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)

                Spacer()

                Button {
                    selectedTab = 1
                } label: {
                    Text("See all")
                        .mangoxFont(.caption)
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
                    VStack(spacing: 6) {
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

import SwiftUI
import SwiftData
import CoreBluetooth
import CoreLocation

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
    @Binding var navigationPath: NavigationPath
    @Binding var selectedTab: Int

    @State private var pendingNavigateOutdoor = false
    @State private var trainingCache: HomeTrainingCache?

    private static let recentWorkoutsDescriptor: FetchDescriptor<Workout> = {
        var d = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 150
        return d
    }()

    @Query(HomeView.recentWorkoutsDescriptor) private var workouts: [Workout]

    @Query private var allProgress: [TrainingPlanProgress]

    private var outdoorButtonDisabled: Bool {
        switch locationManager.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    // MARK: - Design System

    private var bg: Color { AppColor.bg }
    private var mango: Color { AppColor.mango }
    private var success: Color { AppColor.success }
    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textSecondary: Color { .white.opacity(AppOpacity.textSecondary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    /// Matches Outdoor / Indoor top-bar pills so both read as one control pair.
    private static let topBarRideButtonWidth: CGFloat = 116

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
                                if !PowerZone.hasSetFTP {
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
               !dataSource.wifiConnectionState.isConnected {
                bleManager.reconnectOrScan()
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            guard pendingNavigateOutdoor else { return }
            if locationManager.isAuthorized {
                pendingNavigateOutdoor = false
                navigationPath.append(AppRoute.outdoorDashboard)
            } else if newStatus == .denied || newStatus == .restricted {
                pendingNavigateOutdoor = false
            }
        }
        .task(id: workouts.count) {
            recomputeTrainingCache()
        }
    }

    private func recomputeTrainingCache() {
        // Single Calendar + date boundary computation shared across all helpers,
        // avoiding 3 independent Calendar.current + startOfWeek calls.
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now

        let weeklyTSS = computeWeeklyTSS(calendar: calendar, startOfWeek: startOfWeek)
        let chronicLoad = computeChronicLoad(fourWeeksAgo: fourWeeksAgo)
        let acwr = chronicLoad > 0 && !workouts.isEmpty ? weeklyTSS / chronicLoad : 0
        trainingCache = HomeTrainingCache(
            weeklyTSS: weeklyTSS,
            chronicLoad: chronicLoad,
            acwr: acwr,
            weekRides: workouts.filter { $0.startDate >= startOfWeek }.count,
            weekBars: weeklyBreakdownComputed(calendar: calendar, startOfWeek: startOfWeek)
        )
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

            HStack(spacing: 8) {
                Button {
                    switch locationManager.authorizationStatus {
                    case .notDetermined:
                        pendingNavigateOutdoor = true
                        locationManager.requestPermission()
                    case .authorizedWhenInUse, .authorizedAlways:
                        navigationPath.append(AppRoute.outdoorDashboard)
                    case .denied, .restricted:
                        break
                    @unknown default:
                        break
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Outdoor")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: Self.topBarRideButtonWidth)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(MangoxPressStyle())
                .opacity(outdoorButtonDisabled ? 0.45 : 1)
                .disabled(outdoorButtonDisabled)
                .accessibilityLabel("Outdoor ride")
                .accessibilityHint("Opens the outdoor ride screen. Location access is used when you allow it.")

                Button {
                    navigationPath.append(AppRoute.indoorRideSetup)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Indoor")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(AppColor.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: Self.topBarRideButtonWidth)
                    .background(mango)
                    .clipShape(Capsule())
                }
                .buttonStyle(MangoxPressStyle())
                .accessibilityLabel("Indoor ride")
                .accessibilityHint("Connect a smart trainer and start an indoor session.")
            }
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

                // ACWR form badge
                HStack(spacing: 5) {
                    Image(systemName: form.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(form.color)
                    Text(form.description)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(form.color)
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
                            .frame(height: maxTSS > 0 && dayData.tss > 0
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
        }
        .padding(16)
        .cardStyle(cornerRadius: 14)
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

    // MARK: - FTP Prompt

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
                    Text("Set Your FTP")
                        .font(.headline)
                        .foregroundStyle(textPrimary)

                    Text("Required for accurate power zones")
                        .font(.subheadline)
                        .foregroundStyle(textSecondary)
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

                Button { selectedTab = 1 } label: {
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
                    Text("Tap Indoor or Outdoor above to ride. Use the Coach tab for your training plan.")
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

    // MARK: - Training Data

    private func computeWeeklyTSS(calendar: Calendar, startOfWeek: Date) -> Double {
        workouts
            .filter { $0.startDate >= startOfWeek }
            .reduce(0) { $0 + $1.tss }
    }

    private func computeChronicLoad(fourWeeksAgo: Date) -> Double {
        let recentWorkouts = workouts.filter { $0.startDate >= fourWeeksAgo }
        guard !recentWorkouts.isEmpty else { return 300 }
        return recentWorkouts.reduce(0) { $0 + $1.tss } / 4.0
    }

    private func weeklyBreakdownComputed(calendar: Calendar, startOfWeek: Date) -> [WeekDayTSS] {
        (0..<7).map { dayOffset in
            let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) ?? startOfWeek
            let dayStart = calendar.startOfDay(for: dayDate)
            let comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
            let rowId = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            let dayLabel = dayStart.formatted(.dateTime.weekday(.narrow))

            let tss = workouts
                .filter { calendar.isDate($0.startDate, inSameDayAs: dayDate) }
                .reduce(0.0) { $0 + $1.tss }

            let color: Color
            if tss == 0 {
                color = .clear
            } else if tss < 50 {
                color = success.opacity(0.6)
            } else if tss < 100 {
                color = AppColor.yellow
            } else if tss < 150 {
                color = mango
            } else {
                color = AppColor.orange
            }

            return WeekDayTSS(id: rowId, day: dayLabel, tss: tss, color: color)
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
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
        .modelContainer(for: [Workout.self, TrainingPlanProgress.self])
        .environment(HealthKitManager())
}

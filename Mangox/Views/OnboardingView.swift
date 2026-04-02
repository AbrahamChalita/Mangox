import SwiftUI
import CoreBluetooth
import UserNotifications
import CoreLocation

/// First-launch onboarding with permission screens.
/// Shown once — persisted via `@AppStorage("hasCompletedOnboarding")`.
///
/// Flow: Welcome → Bluetooth → HealthKit → Notifications → Location → Strava → Get Started
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(StravaService.self) private var stravaService
    @State private var currentPage = 0
    @State private var blePermissionGranted = false
    @State private var healthKitGranted = false
    @State private var locationGranted = false
    @State private var notificationsGranted = false
    @State private var stravaStatus: String?
    @State private var bleTrigger: CBCentralManager?

    private let totalPages = 7

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    bluetoothPage.tag(1)
                    healthKitPage.tag(2)
                    notificationsPage.tag(3)
                    locationPage.tag(4)
                    stravaPage.tag(5)
                    getStartedPage.tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                Spacer()

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? AppColor.mango : Color.white.opacity(0.15))
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.25), value: currentPage)
                    }
                }
                .padding(.bottom, 32)

                // Action button
                actionButton
                    .padding(.horizontal, 32)

                // Skip / Maybe Later
                if currentPage < totalPages - 1 {
                    Button(isPermissionPage ? "Maybe Later" : "Skip") {
                        withAnimation { advancePage() }
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                } else {
                    Spacer().frame(height: 56)
                }
            }
        }
        .task {
            locationManager.setup()
            blePermissionGranted = CBManager.authorization == .allowedAlways
            healthKitGranted = healthKitManager.isAuthorized
            locationGranted = locationManager.isAuthorized
            notificationsGranted = await notificationPermissionGranted()
            if stravaService.isConnected {
                stravaStatus = "Connected as \(stravaService.athleteDisplayName ?? "Strava athlete")."
            }
        }
    }

    // MARK: - Permission Page Check

    private var isPermissionPage: Bool {
        (1...4).contains(currentPage)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            handleAction()
        } label: {
            Text(buttonTitle)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.mango)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(MangoxPressStyle())
    }

    private var buttonTitle: String {
        switch currentPage {
        case 0: return "Continue"
        case 1: return blePermissionGranted ? "Continue" : "Enable Bluetooth"
        case 2: return healthKitGranted ? "Continue" : "Enable Health"
        case 3: return notificationsGranted ? "Continue" : "Enable Notifications"
        case 4: return locationGranted ? "Continue" : "Enable Location"
        case 5:
            if stravaService.isBusy { return "Connecting..." }
            if stravaService.isConnected { return "Continue" }
            return stravaService.isConfigured ? "Connect Strava" : "Continue"
        case 6: return "Get Started"
        default: return "Continue"
        }
    }

    private func handleAction() {
        switch currentPage {
        case 1:
            if !blePermissionGranted {
                requestBluetooth()
            } else {
                withAnimation { advancePage() }
            }
        case 2:
            if !healthKitGranted {
                requestHealthKit()
            } else {
                withAnimation { advancePage() }
            }
        case 3:
            if !notificationsGranted {
                requestNotifications()
            } else {
                withAnimation { advancePage() }
            }
        case 4:
            if !locationGranted {
                requestLocation()
            } else {
                withAnimation { advancePage() }
            }
        case 5:
            if stravaService.isConnected || !stravaService.isConfigured {
                withAnimation { advancePage() }
            } else {
                connectStrava()
            }
        case 6:
            hasCompletedOnboarding = true
        default:
            withAnimation { advancePage() }
        }
    }

    private func advancePage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        }
    }

    // MARK: - Permission Requests

    private func requestBluetooth() {
        // Creating a CBCentralManager triggers the system Bluetooth permission dialog.
        bleTrigger = CBCentralManager(delegate: nil, queue: nil)
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(250))
                let granted = CBManager.authorization == .allowedAlways
                await MainActor.run {
                    blePermissionGranted = granted
                }
                if CBManager.authorization != .notDetermined {
                    break
                }
            }
            await MainActor.run {
                withAnimation { advancePage() }
            }
        }
    }

    private func requestHealthKit() {
        Task {
            await healthKitManager.requestAuthorization()
            await MainActor.run {
                healthKitGranted = healthKitManager.isAuthorized
                withAnimation { advancePage() }
            }
        }
    }

    private func requestLocation() {
        locationManager.requestPermission()
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                if locationManager.authorizationStatus != .notDetermined {
                    break
                }
            }
            await MainActor.run {
                locationGranted = locationManager.isAuthorized
                withAnimation { advancePage() }
            }
        }
    }

    private func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    notificationsGranted = granted
                    withAnimation { advancePage() }
                }
            } catch {
                await MainActor.run {
                    withAnimation { advancePage() }
                }
            }
        }
    }

    private func connectStrava() {
        Task {
            do {
                try await stravaService.connect()
                await MainActor.run {
                    stravaStatus = "Connected as \(stravaService.athleteDisplayName ?? "Strava athlete")."
                    withAnimation { advancePage() }
                }
            } catch {
                await MainActor.run {
                    stravaStatus = error.localizedDescription
                }
            }
        }
    }

    private func notificationPermissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPageView(
            icon: "figure.outdoor.cycle",
            title: "Welcome to Mangox",
            subtitle: "Your personal cycling studio — indoors on your smart trainer, or outdoors replacing your bike computer.",
            color: AppColor.mango,
            extraContent: {
                VStack(spacing: 8) {
                    featureRow(icon: "antenna.radiowaves.left.and.right", text: "Connect smart trainers & sensors")
                    featureRow(icon: "map.fill", text: "GPS outdoor rides with navigation")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "Structured training & analytics")
                    featureRow(icon: "paperplane.fill", text: "Sync to Strava automatically")
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        )
    }

    private var bluetoothPage: some View {
        OnboardingPageView(
            icon: "antenna.radiowaves.left.and.right",
            title: "Connect Your Gear",
            subtitle: "Mangox uses Bluetooth to connect to your smart trainer, heart rate monitor, and power meter.",
            color: AppColor.blue,
            granted: blePermissionGranted,
            extraContent: {
                permissionNote("Required for indoor training. Also works outdoors with BLE sensors.")
            }
        )
    }

    private var healthKitPage: some View {
        OnboardingPageView(
            icon: "heart.text.square.fill",
            title: "Health Data",
            subtitle: "Read your resting heart rate, max HR, and VO2 Max to calculate accurate training zones.",
            color: AppColor.heartRate,
            granted: healthKitGranted,
            extraContent: {
                permissionNote("We only read health data — Mangox never writes to HealthKit.")
            }
        )
    }

    private var locationPage: some View {
        OnboardingPageView(
            icon: "location.fill",
            title: "GPS Location",
            subtitle: "Track outdoor rides with live speed, distance, elevation, and route recording right on your phone.",
            color: AppColor.success,
            granted: locationGranted,
            extraContent: {
                permissionNote("Used only during outdoor rides. Never tracked in the background when not riding.")
            }
        )
    }

    private var notificationsPage: some View {
        OnboardingPageView(
            icon: "bell.badge.fill",
            title: "Stay On Track",
            subtitle: "Get workout reminders, plan nudges, and important ride alerts without opening the app.",
            color: AppColor.orange,
            granted: notificationsGranted,
            extraContent: {
                permissionNote("We'll keep it minimal — no spam, just useful ride alerts.")
            }
        )
    }

    private var stravaPage: some View {
        OnboardingPageView(
            icon: "paperplane.fill",
            title: "Share With Strava",
            subtitle: "One tap to upload your ride after every session. You can connect Strava anytime from your profile.",
            color: AppColor.strava,
            granted: stravaService.isConnected,
            extraContent: {
                VStack(spacing: 10) {
                    if let stravaStatus {
                        Text(stravaStatus)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    permissionNote("Optional — connect from Settings whenever you're ready.")
                }
            }
        )
    }

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColor.mango.opacity(0.08))
                    .frame(width: 200, height: 200)
                Circle()
                    .fill(AppColor.mango.opacity(0.04))
                    .frame(width: 260, height: 260)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(AppColor.mango)
            }

            VStack(spacing: 12) {
                Text("You're All Set")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("Connect your trainer to ride indoors, or start an outdoor ride with GPS. Let's go.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Helper Views

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColor.mango.opacity(0.7))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
    }

    private func permissionNote(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }
}

// MARK: - Single Page View

private struct OnboardingPageView<ExtraContent: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var granted: Bool = false
    let extraContent: () -> ExtraContent

    init(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        granted: Bool = false,
        @ViewBuilder extraContent: @escaping () -> ExtraContent = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.granted = granted
        self.extraContent = extraContent
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 160, height: 160)
                Circle()
                    .fill(color.opacity(0.05))
                    .frame(width: 200, height: 200)
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(color)

                // Granted checkmark overlay
                if granted {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(AppColor.success)
                                .background(
                                    Circle()
                                        .fill(AppColor.bg)
                                        .frame(width: 24, height: 24)
                                )
                        }
                        Spacer()
                    }
                    .frame(width: 160, height: 160)
                }
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 40)

            extraContent()

            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
        .environment(HealthKitManager())
        .environment(LocationManager())
}

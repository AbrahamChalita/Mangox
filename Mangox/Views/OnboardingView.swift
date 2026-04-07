import SwiftUI
import CoreBluetooth
import UserNotifications
import CoreLocation

// MARK: - Hero graphic

private enum OnboardingHeroGraphic {
    case sfSymbol(String)
    case brandAsset(String)
}

/// First-launch onboarding with permission screens.
/// Shown once — persisted via `@AppStorage("hasCompletedOnboarding")`.
///
/// Flow: Welcome → Bluetooth → HealthKit → Notifications → Location → Strava → Get Started
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(LocationManager.self) private var locationManager
    @Environment(StravaService.self) private var stravaService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage = 0
    @State private var blePermissionGranted = false
    @State private var healthKitGranted = false
    @State private var locationGranted = false
    @State private var notificationsGranted = false
    @State private var stravaStatus: String?
    @State private var bleTrigger: CBCentralManager?
    @State private var welcomeAppeared = false
    @State private var finishCelebration = false
    @State private var onboardingWeightKg: Double = RidePreferences.shared.riderWeightKg
    @State private var onboardingBirthYear: Int = RidePreferences.shared.riderBirthYear ?? (Calendar.current.component(.year, from: .now) - 30)

    private let totalPages = 8

    private var pageAccent: Color {
        switch currentPage {
        case 0: return AppColor.mango
        case 1: return AppColor.blue
        case 2: return AppColor.heartRate
        case 3: return AppColor.orange
        case 4: return AppColor.success
        case 5: return AppColor.strava
        default: return AppColor.mango
        }
    }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()
            OnboardingAmbientBackground(accent: pageAccent, reduceMotion: reduceMotion)

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    bluetoothPage.tag(1)
                    healthKitPage.tag(2)
                    notificationsPage.tag(3)
                    locationPage.tag(4)
                    stravaPage.tag(5)
                    riderProfilePage.tag(6)
                    getStartedPage.tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.35), value: currentPage)

                Spacer()

                progressSection
                    .padding(.bottom, 20)

                actionButton
                    .padding(.horizontal, 32)

                if currentPage < totalPages - 1 {
                    Button(isPermissionPage ? "Maybe Later" : "Skip") {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                } else {
                    Spacer().frame(height: 56)
                }
            }
        }
        .onAppear {
            syncWelcomeAppearance()
        }
        .onChange(of: reduceMotion) { _, _ in
            syncWelcomeAppearance()
        }
        .onChange(of: currentPage) { _, new in
            if new == 0 {
                syncWelcomeAppearance()
            }
            if new == 7 {
                triggerFinishCelebrationIfNeeded()
            }
        }
        .onChange(of: blePermissionGranted) { _, new in
            if new, currentPage == 1 { HapticManager.shared.onboardingStepCompleted() }
        }
        .onChange(of: healthKitGranted) { _, new in
            if new, currentPage == 2 { HapticManager.shared.onboardingStepCompleted() }
        }
        .onChange(of: notificationsGranted) { _, new in
            if new, currentPage == 3 { HapticManager.shared.onboardingStepCompleted() }
        }
        .onChange(of: locationGranted) { _, new in
            if new, currentPage == 4 { HapticManager.shared.onboardingStepCompleted() }
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

    private func syncWelcomeAppearance() {
        if reduceMotion {
            welcomeAppeared = true
        } else if currentPage == 0 {
            welcomeAppeared = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    welcomeAppeared = true
                }
            }
        }
    }

    private func triggerFinishCelebrationIfNeeded() {
        guard !reduceMotion else {
            finishCelebration = true
            return
        }
        finishCelebration = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                finishCelebration = true
            }
        }
    }

    // MARK: - Progress (page dots only)

    private var progressSection: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? AppColor.mango : Color.white.opacity(0.15))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: currentPage)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(totalPages)")
    }

    // MARK: - Permission Page Check

    /// Pages where the primary button requests a system permission. Notifications (page 3) is informational only.
    private var isPermissionPage: Bool {
        switch currentPage {
        case 1, 2, 4: return true
        default: return false
        }
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            handleAction()
        } label: {
            Text(buttonTitle)
                .font(.body.weight(.bold))
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
        case 3: return "Continue"
        case 4: return locationGranted ? "Continue" : "Enable Location"
        case 5:
            if stravaService.isBusy { return "Connecting..." }
            if stravaService.isConnected { return "Continue" }
            return stravaService.isConfigured ? "Connect Strava" : "Continue"
        case 6: return "Continue"
        case 7: return "Get Started"
        default: return "Continue"
        }
    }

    private func handleAction() {
        switch currentPage {
        case 1:
            if !blePermissionGranted {
                requestBluetooth()
            } else {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
            }
        case 2:
            if !healthKitGranted {
                requestHealthKit()
            } else {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
            }
        case 3:
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
        case 4:
            if !locationGranted {
                requestLocation()
            } else {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
            }
        case 5:
            if stravaService.isConnected || !stravaService.isConfigured {
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
            } else {
                connectStrava()
            }
        case 6:
            // Save rider profile and advance
            let prefs = RidePreferences.shared
            prefs.riderWeightKg = onboardingWeightKg
            prefs.riderBirthYear = onboardingBirthYear
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
        case 7:
            HapticManager.shared.onboardingCelebration()
            hasCompletedOnboarding = true
        default:
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
        }
    }

    private func advancePage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        }
    }

    // MARK: - Permission Requests

    private func requestBluetooth() {
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
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
            }
        }
    }

    private func requestHealthKit() {
        Task {
            await healthKitManager.requestAuthorization()
            await MainActor.run {
                healthKitGranted = healthKitManager.isAuthorized
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
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
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
            }
        }
    }

    private func connectStrava() {
        Task {
            do {
                try await stravaService.connect()
                await MainActor.run {
                    stravaStatus = "Connected as \(stravaService.athleteDisplayName ?? "Strava athlete")."
                    HapticManager.shared.onboardingCelebration()
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { advancePage() }
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
        OnboardingWelcomePage(
            welcomeAppeared: welcomeAppeared,
            reduceMotion: reduceMotion,
            featureRows: {
                VStack(spacing: 8) {
                    featureRow(icon: "antenna.radiowaves.left.and.right", text: "Smart trainers, power, HR, and sensors")
                    featureRow(icon: "map.fill", text: "Outdoor GPS rides with routes and navigation")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "PMC, power curve, adaptive plan load")
                    featureRow(icon: "sparkles", text: "AI coach and calendar export (.ics)")
                    featureRow(icon: "paperplane.fill", text: "Optional Strava upload and Apple Health")
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        )
    }

    private var bluetoothPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("antenna.radiowaves.left.and.right"),
            title: "Connect Your Gear",
            subtitle: "Mangox uses Bluetooth to connect to your smart trainer, heart rate monitor, and power meter.",
            color: AppColor.blue,
            granted: blePermissionGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote("Required for indoor training. Also works outdoors with BLE sensors.")
            }
        )
    }

    private var healthKitPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("heart.text.square.fill"),
            title: "Health Data",
            subtitle: "Read resting HR, max HR, and VO2 Max for zones. You can opt in later to save finished rides to the Fitness app.",
            color: AppColor.heartRate,
            granted: healthKitGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote(
                    "Reads are used for zones. Saving rides to Apple Health is optional in Settings → Heart Rate."
                )
            }
        )
    }

    private var locationPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("location.fill"),
            title: "GPS Location",
            subtitle: "Track outdoor rides with live speed, distance, elevation, and route recording right on your phone.",
            color: AppColor.success,
            granted: locationGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote("Used only during outdoor rides. Never tracked in the background when not riding.")
            }
        )
    }

    private var notificationsPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("bell.badge.fill"),
            title: "Stay On Track",
            subtitle:
                "You can turn on workout reminders and plan nudges later in Settings → Data, privacy & alerts — and iOS will ask for notification permission only when you opt in there.",
            color: AppColor.orange,
            granted: notificationsGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote(
                    "We don’t request notification access during onboarding so you stay in control.")
            }
        )
    }

    private var stravaPage: some View {
        OnboardingPageView(
            hero: .brandAsset("BrandStrava"),
            title: "Share With Strava",
            subtitle: "One tap to upload your ride after every session. You can connect Strava anytime from your profile.",
            color: AppColor.strava,
            granted: stravaService.isConnected,
            reduceMotion: reduceMotion,
            extraContent: {
                VStack(spacing: 12) {
                    if stravaService.isConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(AppColor.success)
                            Text("Strava connected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    if let stravaStatus {
                        Text(stravaStatus)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    permissionNote("Optional — connect from Settings whenever you're ready.")
                }
            }
        )
    }

    private var riderProfilePage: some View {
        OnboardingPageView(
            hero: .sfSymbol("figure.outdoor.cycle"),
            title: "Your Rider Profile",
            subtitle: "Enter your weight and age for accurate W/kg, calorie estimates, and personalized AI coaching.",
            color: AppColor.blue,
            reduceMotion: reduceMotion,
            extraContent: {
                VStack(spacing: 16) {
                    // Weight
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("WEIGHT")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .tracking(1.2)
                            let displayWeight = RidePreferences.shared.isImperial
                                ? onboardingWeightKg * 2.20462
                                : onboardingWeightKg
                            let unit = RidePreferences.shared.isImperial ? "lb" : "kg"
                            Text(String(format: "%.0f %@", displayWeight, unit))
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Stepper("", value: Binding(
                            get: {
                                RidePreferences.shared.isImperial
                                    ? (onboardingWeightKg * 2.20462).rounded()
                                    : onboardingWeightKg
                            },
                            set: { newVal in
                                onboardingWeightKg = RidePreferences.shared.isImperial
                                    ? (newVal / 2.20462) : newVal
                            }
                        ), in: RidePreferences.shared.isImperial ? 66.0...440.0 : 30.0...200.0,
                        step: RidePreferences.shared.isImperial ? 1.0 : 0.5)
                        .labelsHidden()
                    }

                    Divider().background(Color.white.opacity(0.08))

                    // Birth year
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("BIRTH YEAR")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.4))
                                .tracking(1.2)
                            let age = Calendar.current.component(.year, from: .now) - onboardingBirthYear
                            Text("\(onboardingBirthYear)  ·  Age \(age)")
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Stepper(
                            "",
                            value: Binding(
                                get: {
                                    let y = Calendar.current.component(.year, from: .now)
                                    return y - onboardingBirthYear
                                },
                                set: { newAge in
                                    let y = Calendar.current.component(.year, from: .now)
                                    onboardingBirthYear = y - newAge
                                }
                            ),
                            in: {
                                let y = Calendar.current.component(.year, from: .now)
                                return (y - 2010)...(y - 1940)
                            }()
                        )
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 32)
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
                    .scaleEffect(finishCelebration ? 1 : 0.92)
                Circle()
                    .fill(AppColor.mango.opacity(0.04))
                    .frame(width: 260, height: 260)
                    .scaleEffect(finishCelebration ? 1 : 0.94)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(AppColor.mango)
                    .scaleEffect(finishCelebration ? 1 : 0.5)
                    .opacity(finishCelebration ? 1 : 0.001)
            }
            .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.68), value: finishCelebration)

            VStack(spacing: 12) {
                Text("You're All Set")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Connect your trainer for indoor rides, or start an outdoor ride with GPS whenever you’re ready.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Helper Views

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColor.mango.opacity(0.75))
                .frame(width: 24)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
            Spacer()
        }
    }

    private func permissionNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }
}

// MARK: - Ambient background

private struct OnboardingAmbientBackground: View {
    let accent: Color
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [
                        accent.opacity(0.22),
                        accent.opacity(0.06),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: geo.size.width * 0.95
                )
                RadialGradient(
                    colors: [
                        AppColor.mango.opacity(0.12),
                        Color.clear,
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: geo.size.height * 0.55
                )
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.7), value: accent)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Welcome page

private struct OnboardingWelcomePage<FeatureRows: View>: View {
    var welcomeAppeared: Bool
    var reduceMotion: Bool
    @ViewBuilder var featureRows: () -> FeatureRows

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.mango.opacity(0.12 - Double(i) * 0.015))
                        .frame(width: 120 - CGFloat(i) * 14, height: 3)
                        .offset(x: CGFloat(i) * 6 + 40, y: CGFloat(i) * 5 - 20)
                        .rotationEffect(.degrees(-18))
                        .opacity(welcomeLineOpacity(index: i))
                        .animation(welcomeAnimation(delay: 0.02 + Double(i) * 0.03), value: welcomeAppeared)
                }

                ZStack {
                    Circle()
                        .fill(AppColor.mango.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .scaleEffect(heroHaloScale)
                    Circle()
                        .fill(AppColor.mango.opacity(0.05))
                        .frame(width: 248, height: 248)
                        .scaleEffect(heroHaloScale * 1.02)

                    Image(systemName: "figure.outdoor.cycle")
                        .font(.system(size: 76, weight: .thin))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColor.mango, AppColor.yellow.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: AppColor.mango.opacity(0.35), radius: 18, y: 8)
                        .opacity(welcomeAppeared ? 1 : 0)
                        .offset(y: welcomeAppeared ? 0 : 16)
                        .animation(welcomeAnimation(delay: 0.06), value: welcomeAppeared)
                }
                .animation(welcomeAnimation(delay: 0.04), value: welcomeAppeared)
            }
            .padding(.bottom, 8)

            VStack(spacing: 10) {
                Text("Train smarter")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(welcomeAppeared ? 1 : 0)
                    .offset(y: welcomeAppeared ? 0 : 16)
                    .animation(welcomeAnimation(delay: 0.14), value: welcomeAppeared)

                Text("Indoor ERG, outdoor GPS, and plans — without juggling another bike computer app.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .opacity(welcomeAppeared ? 1 : 0)
                    .offset(y: welcomeAppeared ? 0 : 16)
                    .animation(welcomeAnimation(delay: 0.22), value: welcomeAppeared)
            }

            featureRows()
                .opacity(welcomeAppeared ? 1 : 0)
                .offset(y: welcomeAppeared ? 0 : 14)
                .animation(welcomeAnimation(delay: 0.3), value: welcomeAppeared)

            Spacer()
        }
    }

    private func welcomeAnimation(delay: Double) -> Animation {
        if reduceMotion { return .linear(duration: 0) }
        return .spring(response: 0.52, dampingFraction: 0.84).delay(delay)
    }

    private func welcomeLineOpacity(index: Int) -> Double {
        if reduceMotion { return 0.35 - Double(index) * 0.04 }
        return welcomeAppeared ? (0.35 - Double(index) * 0.04) : 0
    }

    private var heroHaloScale: CGFloat {
        if reduceMotion { return 1 }
        return welcomeAppeared ? 1 : 0.94
    }
}

// MARK: - Standard permission / integration page

private struct OnboardingPageView<ExtraContent: View>: View {
    let hero: OnboardingHeroGraphic
    let title: String
    let subtitle: String
    let color: Color
    var granted: Bool = false
    var reduceMotion: Bool
    let extraContent: () -> ExtraContent

    @State private var pulseLarge = false
    @State private var checkPop = false

    init(
        hero: OnboardingHeroGraphic,
        title: String,
        subtitle: String,
        color: Color,
        granted: Bool = false,
        reduceMotion: Bool,
        @ViewBuilder extraContent: @escaping () -> ExtraContent = { EmptyView() }
    ) {
        self.hero = hero
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.granted = granted
        self.reduceMotion = reduceMotion
        self.extraContent = extraContent
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .scaleEffect(outerRingScale)
                Circle()
                    .fill(color.opacity(0.05))
                    .frame(width: 200, height: 200)
                    .scaleEffect(innerRingScale)

                heroView
                    .accessibilityHidden(true)

                if granted {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppColor.success)
                                .background(
                                    Circle()
                                        .fill(AppColor.bg)
                                        .frame(width: 26, height: 26)
                                )
                                .scaleEffect(checkPop ? 1 : 0.2)
                                .opacity(checkPop ? 1 : 0)
                        }
                        Spacer()
                    }
                    .frame(width: 160, height: 160)
                }
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            extraContent()

            Spacer()
        }
        .onAppear {
            startPulseIfNeeded()
            syncCheckmark(animated: false)
        }
        .onChange(of: granted) { _, new in
            syncCheckmark(animated: true)
        }
        .onChange(of: reduceMotion) { _, _ in
            startPulseIfNeeded()
        }
    }

    @ViewBuilder
    private var heroView: some View {
        switch hero {
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(color)
        case .brandAsset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .foregroundStyle(color)
        }
    }

    private var outerRingScale: CGFloat {
        if reduceMotion { return 1 }
        return pulseLarge ? 1.04 : 1
    }

    private var innerRingScale: CGFloat {
        if reduceMotion { return 1 }
        return pulseLarge ? 1.025 : 1
    }

    private func startPulseIfNeeded() {
        guard !reduceMotion else {
            pulseLarge = false
            return
        }
        pulseLarge = false
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulseLarge = true
        }
    }

    private func syncCheckmark(animated: Bool) {
        if granted {
            if reduceMotion || !animated {
                checkPop = true
            } else {
                checkPop = false
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                    checkPop = true
                }
            }
        } else {
            checkPop = false
        }
    }
}

#Preview {
    OnboardingView()
        .environment(HealthKitManager())
        .environment(LocationManager())
        .environment(StravaService())
}

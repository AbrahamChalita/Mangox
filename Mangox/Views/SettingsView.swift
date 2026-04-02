import SwiftUI

/// Account, health, training zones, and app preferences in one place.
struct SettingsView: View {
    @Environment(PurchasesManager.self) private var purchases
    @Environment(StravaService.self) private var stravaService

    @State private var settingsPath = NavigationPath()
    @State private var showPaywall = false

    @Bindable private var prefs = RidePreferences.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack(path: $settingsPath) {
            ZStack {
                AppColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear
                            .frame(height: 4)

                        settingsIdentityHeader

                        profileSectionHeader(
                            title: "Fitness & zones",
                            subtitle: "Heart rate limits, FTP, and Apple Health — your baselines for training zones."
                        )
                        FitnessZonesProfileCard()
                            .padding(.horizontal, 20)

                        profileSectionHeader(
                            title: "Connections",
                            subtitle: "Cloud accounts for ride uploads and sync — separate from your zone settings."
                        )
                        StravaConnectionCard()
                            .padding(.horizontal, 20)

                        profileSectionHeader(
                            title: "Ride preferences",
                            subtitle: "How Mangox displays metrics, speed, outdoor sensors, and feedback during rides."
                        )

                        preferenceGroupHeader("General")
                        settingsCardPlain {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Unit system")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                                Picker("Unit System", selection: $prefs.unitSystem) {
                                    ForEach(UnitSystem.allCases, id: \.self) { system in
                                        Text(system.label).tag(system)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Divider().background(Color.white.opacity(0.06))

                                settingsToggle(
                                    title: "Show Laps",
                                    subtitle: "Display lap counter during rides",
                                    isOn: $prefs.showLaps
                                )

                                Divider().background(Color.white.opacity(0.06))

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Indoor main power")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text("Large power number and zones during indoor rides and the FTP test. Saved workouts, energy, and normalized power always use per-second averages of raw trainer data.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.38))
                                    Picker("Indoor main power", selection: $prefs.indoorPowerHeroMode) {
                                        ForEach(IndoorPowerHeroMode.allCases, id: \.self) { mode in
                                            Text(mode.label).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(AppColor.mango)
                                }
                            }
                        }

                        preferenceGroupHeader("Indoor trainer")
                        settingsCardPlain {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Speed source")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("Trainer-reported uses your trainer's internal model. Computed derives speed from power using physics.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.38))
                                Picker("Speed source", selection: $prefs.indoorSpeedSource) {
                                    ForEach(IndoorSpeedSource.allCases, id: \.self) { source in
                                        Text(source.label).tag(source)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            if prefs.indoorSpeedSource == .computed {
                                Divider().background(Color.white.opacity(0.06))

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Rider weight")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Slider(
                                        value: $prefs.riderWeightKg,
                                        in: RidePreferences.riderWeightRange,
                                        step: 1
                                    )
                                    .tint(AppColor.mango)
                                    HStack {
                                        Text("Body weight")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.45))
                                        Spacer()
                                        Text("\(Int(prefs.riderWeightKg)) kg")
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AppColor.mango)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Bike weight")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Slider(
                                        value: $prefs.bikeWeightKg,
                                        in: RidePreferences.bikeWeightRange,
                                        step: 0.5
                                    )
                                    .tint(AppColor.mango)
                                    HStack {
                                        Text("Bike weight")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.45))
                                        Spacer()
                                        Text("\(String(format: "%.1f", prefs.bikeWeightKg)) kg")
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AppColor.mango)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Aerodynamic drag (CdA)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Text("Lower = more aerodynamic. Drops ≈ 0.28, hoods ≈ 0.32, upright ≈ 0.35")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.38))
                                    Slider(
                                        value: $prefs.riderCda,
                                        in: RidePreferences.cdaRange,
                                        step: 0.01
                                    )
                                    .tint(AppColor.mango)
                                    HStack {
                                        Text("CdA")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.45))
                                        Spacer()
                                        Text(String(format: "%.2f m²", prefs.riderCda))
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(AppColor.mango)
                                    }
                                }
                            }
                        }

                        preferenceGroupHeader("Outdoor & sensors")
                        settingsCardPlain {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("GPS auto-lap")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("Outdoor rides split by distance along your path. Off disables GPS auto-laps.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.38))
                                Picker("Interval", selection: $prefs.outdoorAutoLapIntervalMeters) {
                                    Text("Off").tag(0.0)
                                    Text("500 m").tag(500.0)
                                    Text("1 km").tag(1000.0)
                                    Text("2 km").tag(2000.0)
                                    Text("5 km").tag(5000.0)
                                    Text("10 km").tag(10_000.0)
                                }
                                .pickerStyle(.menu)
                                .tint(AppColor.mango)
                            }

                            settingsToggle(
                                title: "Prioritize navigation (mapless)",
                                subtitle: "Keeps next turn and route context near the top when the map is hidden on iPhone",
                                isOn: $prefs.prioritizeNavigationInMaplessBikeComputer
                            )
                            settingsToggle(
                                title: "Lock Screen ride status",
                                subtitle: "Lock screen and Dynamic Island ride status while recording. Requires Live Activities enabled in Settings › Mangox.",
                                isOn: $prefs.outdoorLiveActivityEnabled
                            )
                            settingsToggle(
                                title: "Indoor ride status",
                                subtitle: "Lock screen and Dynamic Island status during indoor rides. Shows power, cadence, and heart rate.",
                                isOn: $prefs.indoorLiveActivityEnabled
                            )

                            Divider().background(Color.white.opacity(0.06))

                            Button {
                                settingsPath.append(AppRoute.outdoorSensorsSetup)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Bluetooth sensors")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                        Text("Pair a heart rate monitor and speed/cadence sensor for outdoor rides.")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.38))
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.28))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().background(Color.white.opacity(0.06))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Speed sensor wheel size")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("Rolling circumference for Bluetooth speed/cadence sensors. Match your tire (printed on the sidewall) for accurate speed.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.38))
                                Slider(
                                    value: $prefs.cscWheelCircumferenceMeters,
                                    in: RidePreferences.cscWheelCircumferenceRange,
                                    step: 0.001
                                )
                                .tint(AppColor.mango)
                                HStack {
                                    Text("Circumference")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.45))
                                    Spacer()
                                    Text("\(Int(prefs.cscWheelCircumferenceMeters * 1000)) mm")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppColor.mango)
                                }
                            }
                        }

                        preferenceGroupHeader("Audio & haptics")
                        settingsCardPlain {
                            settingsToggle(
                                title: "Audio Cues",
                                subtitle: "Spoken zone changes and milestones",
                                isOn: $prefs.stepAudioCueEnabled
                            )
                            settingsToggle(
                                title: "Outdoor Turn Cues",
                                subtitle: "Spoken and haptic prompts for navigation and GPX bends",
                                isOn: $prefs.navigationTurnCuesEnabled
                            )
                        }

                        preferenceGroupHeader("Cadence")
                        settingsCardPlain {
                            settingsToggle(
                                title: "Low Cadence Warning",
                                subtitle: "Nudge when cadence drops below threshold",
                                isOn: $prefs.lowCadenceWarningEnabled
                            )
                            if prefs.lowCadenceWarningEnabled {
                                HStack {
                                    Text("Threshold")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Spacer()
                                    Stepper("\(prefs.lowCadenceThreshold) rpm", value: Binding(
                                        get: { prefs.lowCadenceThreshold },
                                        set: { prefs.lowCadenceThreshold = max(30, min(120, $0)) }
                                    ), in: 30...120, step: 5)
                                    .frame(width: 160)
                                }
                                .padding(.top, 4)
                            }
                        }

                        profileSectionHeader(
                            title: "App data",
                            subtitle: "Onboarding and local data — not your training zones or connections."
                        )
                        settingsCardPlain {
                            Button {
                                resetOnboarding()
                            } label: {
                                HStack {
                                    Text("Show Onboarding Again")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Spacer()
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                            }
                        }

                        profileSectionHeader(
                            title: "Subscription",
                            subtitle: "Mangox Pro features and billing."
                        )
                        subscriptionSection

                        profileSectionHeader(
                            title: "About",
                            subtitle: "App version and build information."
                        )
                        settingsCardPlain {
                            HStack {
                                Text("Version")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }

                        Spacer().frame(height: 40)
                    }
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .navigationDestination(for: AppRoute.self) { route in
                    if case .outdoorSensorsSetup = route {
                        ConnectionView(navigationPath: $settingsPath, outdoorSensorsOnly: true)
                            .toolbar(.hidden, for: .tabBar)
                    }
                }
            }
        }
        .keyboardDismissToolbar()
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Identity header

    private var settingsIdentityHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            settingsIdentityAvatar
            VStack(alignment: .leading, spacing: 4) {
                Text(settingsIdentityPrimaryTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(settingsIdentitySubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var settingsIdentityPrimaryTitle: String {
        if stravaService.isConnected {
            let trimmed = stravaService.athleteDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "Strava" : trimmed
        }
        return "Mangox"
    }

    private var settingsIdentitySubtitle: String {
        stravaService.isConnected ? "Strava connected" : "Settings, zones, and connections"
    }

    @ViewBuilder
    private var settingsIdentityAvatar: some View {
        if let url = stravaService.athleteProfileImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    settingsIdentityPlaceholder
                case .empty:
                    ProgressView()
                        .tint(AppColor.mango)
                @unknown default:
                    settingsIdentityPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        } else {
            settingsIdentityPlaceholder
        }
    }

    private var settingsIdentityPlaceholder: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 26))
            .foregroundStyle(AppColor.mango.opacity(0.95))
            .frame(width: 56, height: 56)
            .background(Color.white.opacity(0.06))
            .clipShape(Circle())
    }

    // MARK: - Section headers

    /// Major profile sections (fitness vs connections vs preferences).
    private func profileSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// Subgroups inside the Ride preferences block (General, Indoor, Outdoor, …).
    private func preferenceGroupHeader(_ name: String) -> some View {
        HStack {
            Text(name.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.32))
                .tracking(1.2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Card Builder

    /// Grouped card without a redundant uppercase title row (section headers provide context).
    private func settingsCardPlain<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .cardStyle(cornerRadius: 16)
        .padding(.horizontal, 20)
    }

    private func settingsToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .tint(AppColor.mango)
    }

    // MARK: - Actions

    private func resetOnboarding() {
        hasCompletedOnboarding = false
    }

    // MARK: - Subscription Section

    @ViewBuilder
    private var subscriptionSection: some View {
        if purchases.isPro {
            mangoxProActiveCard
        } else {
            mangoxProUpgradeCard
        }
    }

    private var mangoxProActiveCard: some View {
        settingsCardPlain {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.mango)
                    Text("Mangox Pro")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.success)
                    Text("Active")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.success)
                }

                if let url = purchases.subscriptionManagementURL {
                    Link(destination: url) {
                        Text("Manage Subscription")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                    }
                }
            }
        }
    }

    private var mangoxProUpgradeCard: some View {
        settingsCardPlain {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.mango)
                    Text("Mangox Pro")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .contentShape(Rectangle())
                .onTapGesture { showPaywall = true }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock Mangox Pro")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Advanced analytics, full training features, and priority updates")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("$4.99/mo")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColor.mango)
                        Text("Monthly")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("$29.99/yr")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColor.mango)
                        Text("Save 50%")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColor.success)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .onTapGesture { showPaywall = true }
            }
        }
    }

}
